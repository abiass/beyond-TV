import 'dart:io';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_server/server.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main(List<String> args) async {
  final ServerConfig config;
  try {
    final parsed = ServerConfig.parse(args, environment: Platform.environment);
    if (parsed == null) {
      stdout
        ..writeln('Uso: server [opções]\n')
        ..writeln(ServerConfig.usage);
      return;
    }
    config = parsed;
  } on ConfigException catch (e) {
    stderr
      ..writeln(e.message)
      ..writeln()
      ..writeln(ServerConfig.usage);
    exit(64); // EX_USAGE
  }

  setupLogging(config.logLevel, sink: stdout.writeln);
  final log = Logger('server');

  final dataDir = Directory(config.dataDir).absolute.path;
  await Directory(dataDir).create(recursive: true);
  final db = openDatabase(p.join(dataDir, databaseFileName));

  if (!Directory(config.webDir).existsSync()) {
    log.warning(
      LogEvent('dashboard não compilado; rode "flutter build web"', {
        'webDir': Directory(config.webDir).absolute.path,
      }),
    );
  }

  final server = await shelf_io.serve(
    buildHandler(
      db: db,
      mediaDir: p.join(dataDir, 'media'),
      webDir: config.webDir,
    ),
    InternetAddress.anyIPv4,
    config.port,
  );
  log.info(
    LogEvent('Beyond TV $serverVersion iniciado', {
      'url': 'http://localhost:${server.port}',
      'dataDir': dataDir,
    }),
  );

  DiscoveryResponder? discovery;
  try {
    discovery = await DiscoveryResponder.bind(
      port: config.discoveryPort,
      response: DiscoveryResponse(
        name: Platform.localHostname,
        port: server.port,
        serverId: DeviceStore(db).serverId,
      ),
    );
    log.info(LogEvent('descoberta ativa', {'udp': discovery.port}));
  } on SocketException catch (e) {
    // Sem descoberta, as TVs ainda conectam pelo IP digitado.
    log.warning(
      LogEvent('descoberta indisponível; use o IP manual nas TVs', {
        'udp': config.discoveryPort,
        'motivo': e.osError?.message ?? e.message,
      }),
    );
  }

  // Encerra de forma limpa com Ctrl+C.
  await ProcessSignal.sigint.watch().first;
  log.info('encerrando');
  await discovery?.close();
  await server.close();
  db.close();
  exit(0);
}
