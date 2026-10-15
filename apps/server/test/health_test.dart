import 'dart:convert';
import 'dart:io';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_server/server.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late Uri baseUri;
  late Database db;

  setUp(() async {
    db = openDatabase();
    server = await shelf_io.serve(
      buildHandler(db: db, mediaDir: 'unused'),
      InternetAddress.loopbackIPv4,
      0, // porta efêmera
    );
    baseUri = Uri.parse('http://${server.address.host}:${server.port}');
  });

  tearDown(() async {
    await server.close(force: true);
    db.close();
  });

  test('GET /health responde ok com versões', () async {
    final response = await http.get(baseUri.resolve('/health'));

    expect(response.statusCode, 200);
    expect(response.headers['content-type'], startsWith('application/json'));
    expect(jsonDecode(response.body), {
      'status': 'ok',
      'version': serverVersion,
      'protocol': protocolVersion,
    });
  });

  test('rota desconhecida responde 404', () async {
    final response = await http.get(baseUri.resolve('/nao-existe'));

    expect(response.statusCode, 404);
  });
}
