import 'package:test/test.dart';

import '../support/realtime_support.dart';
import '../support/test_server.dart';

void main() {
  late TestServer server;
  late Map<String, String> admin;

  setUp(() async {
    server = await TestServer.start();
    admin = await setupAdmin(server);
  });

  Future<String> create([String url = 'https://a.local']) async {
    final r = await server.post(
      '/api/v1/media',
      json: {'kind': 'url', 'url': url},
      headers: admin,
    );
    return (jsonBody(r)! as Map)['id'] as String;
  }

  test('exige sessão', () async {
    expect((await server.get('/api/v1/media')).statusCode, 401);
    expect((await server.post('/api/v1/media', json: {})).statusCode, 401);
    expect((await server.send('PATCH', '/api/v1/media/x')).statusCode, 401);
    expect((await server.send('DELETE', '/api/v1/media/x')).statusCode, 401);
  });

  test('recusa URLs inseguras', () async {
    for (final url in ['javascript:alert(1)', 'file:///x', 'ftp://x']) {
      final r = await server.post(
        '/api/v1/media',
        json: {'kind': 'url', 'url': url},
        headers: admin,
      );
      expect(r.statusCode, 400);
      expect(errorCode(r), 'invalid_url');
    }
  });

  test('recusa outro kind', () async {
    final r = await server.post(
      '/api/v1/media',
      json: {'kind': 'image', 'url': 'https://a.local'},
      headers: admin,
    );
    expect(r.statusCode, 400);
    expect(errorCode(r), 'bad_request');
  });

  test('cria e lista', () async {
    final r = await server.post(
      '/api/v1/media',
      json: {'kind': 'url', 'url': 'https://a.local/x', 'name': 'Painel'},
      headers: admin,
    );
    expect(r.statusCode, 201);
    expect((jsonBody(r)! as Map)['name'], 'Painel');

    final list = await server.get('/api/v1/media', headers: admin);
    expect(((jsonBody(list)! as Map)['media'] as List), hasLength(1));
  });

  test('PATCH atualiza ou responde 404', () async {
    final id = await create();

    final ok = await server.send(
      'PATCH',
      '/api/v1/media/$id',
      json: {'name': 'Novo'},
      headers: admin,
    );
    final bad = await server.send(
      'PATCH',
      '/api/v1/media/$id',
      json: {'url': 'ftp://x'},
      headers: admin,
    );
    final missing = await server.send(
      'PATCH',
      '/api/v1/media/nada',
      json: {'name': 'x'},
      headers: admin,
    );

    expect(ok.statusCode, 200);
    expect((jsonBody(ok)! as Map)['name'], 'Novo');
    expect(bad.statusCode, 400);
    expect(missing.statusCode, 404);
  });

  test('DELETE responde 204 e depois 404', () async {
    final id = await create();

    final first = await server.send(
      'DELETE',
      '/api/v1/media/$id',
      headers: admin,
    );
    final second = await server.send(
      'DELETE',
      '/api/v1/media/$id',
      headers: admin,
    );

    expect(first.statusCode, 204);
    expect(second.statusCode, 404);
  });
}
