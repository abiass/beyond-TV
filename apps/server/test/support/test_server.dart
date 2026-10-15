import 'dart:convert';
import 'dart:io';

import 'package:beyond_server/server.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// bcrypt com o custo mínimo, para os testes não demorarem.
const fastHasher = PasswordHasher(cost: 4);

/// Servidor real numa porta efêmera com banco em memória.
///
/// É encerrado automaticamente no fim do teste.
class TestServer {
  TestServer._(this.db, this.mediaDir, this._server);

  static Future<TestServer> start({
    Clock clock = DateTime.now,
    Handler Function(Database db, String mediaDir)? handler,
  }) async {
    final db = openDatabase();
    final mediaDir = Directory.systemTemp.createTempSync('beyond_media_').path;
    addTearDown(() => Directory(mediaDir).deleteSync(recursive: true));
    final server = await shelf_io.serve(
      handler?.call(db, mediaDir) ??
          buildHandler(
            db: db,
            mediaDir: mediaDir,
            hasher: fastHasher,
            clock: clock,
          ),
      InternetAddress.loopbackIPv4,
      0,
    );
    final testServer = TestServer._(db, mediaDir, server);
    addTearDown(testServer.close);
    return testServer;
  }

  final Database db;

  /// Pasta dos arquivos de mídia (temporária, apagada no fim do teste).
  final String mediaDir;
  final HttpServer _server;

  Uri uri(String path) =>
      Uri.parse('http://${_server.address.host}:${_server.port}$path');

  Future<http.Response> get(String path, {Map<String, String>? headers}) =>
      http.get(uri(path), headers: headers);

  Future<http.Response> post(
    String path, {
    Object? json,
    Map<String, String>? headers,
  }) => http.post(
    uri(path),
    headers: {'content-type': 'application/json', ...?headers},
    body: json == null ? null : jsonEncode(json),
  );

  /// Requisição com [method] arbitrário (`PATCH`, `DELETE`...).
  Future<http.Response> send(
    String method,
    String path, {
    Object? json,
    Map<String, String>? headers,
  }) async {
    final request = http.Request(method, uri(path))
      ..headers.addAll({
        if (json != null) 'content-type': 'application/json',
        ...?headers,
      });
    if (json != null) request.body = jsonEncode(json);
    return http.Response.fromStream(await request.send());
  }

  Future<void> close() async {
    await _server.close(force: true);
    db.close();
  }
}

/// Corpo JSON de [response].
Object? jsonBody(http.Response response) => jsonDecode(response.body);

/// Código de erro (`error.code`) de [response].
Object? errorCode(http.Response response) =>
    (jsonBody(response)! as Map)['error']['code'];

/// Token do cookie de sessão gravado por [response], se houver.
String? sessionTokenFrom(http.Response response) {
  final match = RegExp(
    '$sessionCookieName=([^;]*)',
  ).firstMatch(response.headers['set-cookie'] ?? '');
  return match?.group(1);
}

/// Cabeçalho `Cookie` com a sessão [token].
Map<String, String> sessionHeader(String token) => {
  'cookie': '$sessionCookieName=$token',
};

/// Relógio manual para os testes avançarem o tempo.
class FakeClock {
  FakeClock([DateTime? start]) : now = start ?? DateTime.utc(2026, 10, 14, 12);

  DateTime now;

  DateTime call() => now;

  void advance(Duration duration) => now = now.add(duration);
}
