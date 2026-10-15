import 'package:test/test.dart';

import '../support/realtime_support.dart';
import '../support/test_server.dart';

void main() {
  late FakeClock clock;
  late TestServer server;
  late Map<String, String> admin;

  setUp(() async {
    clock = FakeClock();
    server = await TestServer.start(clock: clock.call);
    admin = await setupAdmin(server);
  });

  Future<List<Map<String, Object?>>> entries([String query = '']) async {
    final r = await server.get('/api/v1/audit$query', headers: admin);
    expect(r.statusCode, 200, reason: r.body);
    return ((jsonBody(r)! as Map)['entries']! as List)
        .cast<Map<String, Object?>>();
  }

  test('exige admin', () async {
    expect((await server.get('/api/v1/audit')).statusCode, 401);
  });

  test('setup aparece sem admin, mutações com admin', () async {
    final tv = insertDevice(server);
    final rename = await server.send(
      'PATCH',
      '/api/v1/devices/${tv.id}',
      json: {'name': 'Recepção 2'},
      headers: admin,
    );
    expect(rename.statusCode, 200);

    final list = await entries();

    expect(list.first['method'], 'PATCH');
    expect(list.first['path'], '/api/v1/devices/${tv.id}');
    expect(list.first['status'], 200);
    expect(list.first['adminName'], 'admin');
    expect(list.first['adminId'], isA<int>());
    expect(list.first['ip'], '127.0.0.1');
    expect(list.last['method'], 'POST');
    expect(list.last['path'], '/api/v1/setup');
    expect(list.last['adminId'], isNull);
    expect(list.last['adminName'], isNull);
  });

  test('login errado entra com status 401 e sem admin', () async {
    final r = await server.post(
      '/api/v1/auth/login',
      json: {'username': 'admin', 'password': 'errada-errada'},
    );
    expect(r.statusCode, 401);

    final first = (await entries()).first;

    expect(first['path'], '/api/v1/auth/login');
    expect(first['status'], 401);
    expect(first['adminId'], isNull);
  });

  test('erros do errorHandler aparecem com o status final', () async {
    final r = await server.send(
      'DELETE',
      '/api/v1/devices/nada',
      headers: admin,
    );
    expect(r.statusCode, 404);
    final anon = await server.send('DELETE', '/api/v1/devices/nada');
    expect(anon.statusCode, 401);

    final list = await entries();

    expect(list[0]['status'], 401);
    expect(list[0]['adminId'], isNull);
    expect(list[1]['status'], 404);
    expect(list[1]['adminId'], isNotNull);
  });

  test('GET não é gravado', () async {
    await server.get('/api/v1/devices', headers: admin);
    await server.get('/health');
    await entries();

    expect(await entries(), hasLength(1)); // só o setup
  });

  test('query, corpo e cookies não são gravados', () async {
    await server.post(
      '/api/v1/media/files?name=segredo',
      json: {'senha': 'corpo-secreto'},
      headers: {...admin, 'x-extra': 'cabecalho-secreto'},
    );

    final rows = server.db.select('SELECT * FROM audit_log').toList();
    final dump = rows.map((r) => r.values.join('|')).join('\n');

    expect(dump, contains('/api/v1/media/files'));
    expect(dump, isNot(contains('segredo')));
    expect(dump, isNot(contains('beyond_session')));
    expect(dump, isNot(contains(admin['cookie']!.split('=').last)));
  });

  test('logout é gravado com o admin que saiu', () async {
    final r = await server.post('/api/v1/auth/logout', headers: admin);
    expect(r.statusCode, inInclusiveRange(200, 204));

    final row = server.db
        .select(
          "SELECT admin_id FROM audit_log WHERE path = '/api/v1/auth/logout'",
        )
        .single;
    expect(row['admin_id'], isNotNull);
  });

  test('paginação por before e validação de limit', () async {
    for (var i = 0; i < 4; i++) {
      await server.post(
        '/api/v1/groups',
        json: {'name': 'G$i'},
        headers: admin,
      );
    }

    final page1 = await entries('?limit=2');
    final page2 = await entries('?limit=2&before=${page1.last['id']}');

    expect(page1, hasLength(2));
    expect(page2, hasLength(2));
    expect(page2.first['id'], lessThan(page1.last['id']! as int));
    expect(page1.first['path'], '/api/v1/groups');

    for (final bad in ['limit=0', 'limit=501', 'limit=x', 'before=x']) {
      final r = await server.get('/api/v1/audit?$bad', headers: admin);
      expect(r.statusCode, 400, reason: bad);
      expect(errorCode(r), 'bad_request');
    }
    expect(await entries('?limit=500'), isNotEmpty);
  });

  test('falha ao gravar não derruba a requisição', () async {
    server.db.execute('DROP TABLE audit_log');

    final r = await server.post(
      '/api/v1/groups',
      json: {'name': 'Salão'},
      headers: admin,
    );

    expect(r.statusCode, 201);
  });

  test('sessão inválida grava admin nulo', () async {
    await server.post(
      '/api/v1/groups',
      json: {'name': 'X'},
      headers: sessionHeader('invalida'),
    );

    final row = server.db
        .select(
          "SELECT admin_id, status FROM audit_log WHERE path LIKE '%groups'",
        )
        .single;
    expect(row['admin_id'], isNull);
    expect(row['status'], 401);
  });
}
