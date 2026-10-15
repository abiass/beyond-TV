import 'dart:convert';
import 'dart:io';

import 'package:beyond_server/server.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

Future<Response> _get(Handler handler, String path) => Future.sync(
  () => handler(Request('GET', Uri.parse('http://localhost$path'))),
);

void main() {
  late Directory root;
  late String webDir;
  late Database db;

  setUp(() async {
    db = openDatabase();
    root = await Directory.systemTemp.createTemp('beyond_web_');
    webDir = p.join(root.path, 'web');
    await Directory(p.join(webDir, 'assets')).create(recursive: true);
    await File(p.join(webDir, 'index.html')).writeAsString('<html>painel');
    await File(p.join(webDir, 'main.dart.js')).writeAsString('main();');
    await File(p.join(root.path, 'segredo.txt')).writeAsString('não sirva');
  });

  tearDown(() async {
    db.close();
    await root.delete(recursive: true);
  });

  group('com o dashboard compilado', () {
    late Handler handler;

    setUp(
      () => handler = buildHandler(
        db: db,
        mediaDir: p.join(root.path, 'media'),
        webDir: webDir,
      ),
    );

    test('serve o index.html na raiz', () async {
      final response = await _get(handler, '/');

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], startsWith('text/html'));
      expect(response.headers['cache-control'], 'no-cache');
      expect(response.headers['x-content-type-options'], 'nosniff');
      expect(await response.readAsString(), '<html>painel');
    });

    test('serve arquivos estáticos', () async {
      final response = await _get(handler, '/main.dart.js');

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('javascript'));
      expect(await response.readAsString(), 'main();');
    });

    test('devolve o index.html para rotas do dashboard', () async {
      final response = await _get(handler, '/tvs/123');

      expect(response.statusCode, 200);
      expect(await response.readAsString(), '<html>painel');
    });

    test('responde 404 para arquivo inexistente', () async {
      final response = await _get(handler, '/nao-existe.js');

      expect(response.statusCode, 404);
    });

    test('não serve arquivos fora da pasta do build', () async {
      final response = await _get(handler, '/..%2Fsegredo.txt');

      expect(response.statusCode, 404);
      expect(await response.readAsString(), isNot(contains('não sirva')));
    });

    test('rotas da API não caem no dashboard', () async {
      for (final path in ['/api/nao-existe', '/api', '/ws/x']) {
        final response = await _get(handler, path);

        expect(response.statusCode, 404, reason: path);
        expect(jsonDecode(await response.readAsString()), {
          'error': {'code': 'not_found', 'message': 'Recurso não encontrado.'},
        });
      }
    });

    test('/health continua funcionando', () async {
      final response = await _get(handler, '/health');

      expect(response.statusCode, 200);
    });
  });

  group('sem o dashboard compilado', () {
    test('explica como compilar ao abrir a raiz', () async {
      final handler = buildHandler(
        db: db,
        mediaDir: p.join(root.path, 'media'),
        webDir: p.join(root.path, 'nao-existe'),
      );

      final response = await _get(handler, '/');

      expect(response.statusCode, 503);
      expect(await response.readAsString(), contains('flutter build web'));
    });

    test('outros caminhos respondem 404', () async {
      final handler = buildHandler(
        db: db,
        mediaDir: p.join(root.path, 'media'),
        webDir: p.join(root.path, 'nao-existe'),
      );

      expect((await _get(handler, '/tvs')).statusCode, 404);
    });
  });
}
