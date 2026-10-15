import 'package:beyond_server/server.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  group('ServerConfig.parse', () {
    test('usa os padrões sem args nem env', () {
      final config = ServerConfig.parse([])!;

      expect(config.port, defaultHttpPort);
      expect(config.discoveryPort, 8788);
      expect(config.dataDir, defaultDataDir);
      expect(config.webDir, defaultWebDir);
    });

    test('lê a porta da descoberta de args ou env', () {
      expect(
        ServerConfig.parse(['--discovery-port', '9001'])!.discoveryPort,
        9001,
      );
      expect(
        ServerConfig.parse(
          [],
          environment: {'BEYOND_DISCOVERY_PORT': '9002'},
        )!.discoveryPort,
        9002,
      );
      expect(
        () => ServerConfig.parse(['--discovery-port', '0']),
        throwsA(isA<ConfigException>()),
      );
    });

    test('lê as variáveis de ambiente', () {
      final config = ServerConfig.parse(
        [],
        environment: {
          'BEYOND_PORT': '9000',
          'BEYOND_DATA_DIR': '/srv/beyond',
          'BEYOND_WEB_DIR': '/srv/web',
        },
      )!;

      expect(config.port, 9000);
      expect(config.dataDir, '/srv/beyond');
      expect(config.webDir, '/srv/web');
    });

    test('argumentos têm prioridade sobre o ambiente', () {
      final config = ServerConfig.parse(
        ['--port', '9100', '-d', 'outra'],
        environment: {'BEYOND_PORT': '9000', 'BEYOND_DATA_DIR': '/srv/beyond'},
      )!;

      expect(config.port, 9100);
      expect(config.dataDir, 'outra');
    });

    test('ignora variáveis de ambiente vazias', () {
      final config = ServerConfig.parse(
        [],
        environment: {'BEYOND_PORT': ' ', 'BEYOND_DATA_DIR': ''},
      )!;

      expect(config.port, defaultHttpPort);
      expect(config.dataDir, defaultDataDir);
    });

    for (final port in ['0', '65536', 'abc', '-1']) {
      test('recusa porta inválida "$port"', () {
        expect(
          () => ServerConfig.parse(['--port=$port']),
          throwsA(isA<ConfigException>()),
        );
      });
    }

    test('lê o nível de log de args ou env, sem diferenciar maiúsculas', () {
      expect(ServerConfig.parse([])!.logLevel, Level.INFO);
      expect(ServerConfig.parse(['--log-level=debug'])!.logLevel, Level.FINE);
      expect(
        ServerConfig.parse(
          [],
          environment: {'BEYOND_LOG_LEVEL': 'WARNING'},
        )!.logLevel,
        Level.WARNING,
      );
    });

    test('recusa nível de log inválido', () {
      expect(
        () => ServerConfig.parse(['--log-level=verbose']),
        throwsA(isA<ConfigException>()),
      );
      expect(
        () => ServerConfig.parse([], environment: {'BEYOND_LOG_LEVEL': 'x'}),
        throwsA(isA<ConfigException>()),
      );
    });

    test('recusa opção desconhecida', () {
      expect(
        () => ServerConfig.parse(['--nao-existe']),
        throwsA(isA<ConfigException>()),
      );
    });

    test('retorna null com --help', () {
      expect(ServerConfig.parse(['--help']), isNull);
      expect(ServerConfig.usage, contains('BEYOND_PORT'));
    });
  });
}
