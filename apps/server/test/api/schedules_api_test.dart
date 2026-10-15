import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/realtime_support.dart';
import '../support/test_server.dart';

void main() {
  late TestServer server;
  late Map<String, String> admin;
  late String playlistId;
  late String tv;
  late int groupId;

  setUp(() async {
    server = await TestServer.start();
    admin = await setupAdmin(server);
    playlistId =
        (jsonBody(
                  await server.post(
                    '/api/v1/playlists',
                    json: {'name': 'Almoço'},
                    headers: admin,
                  ),
                )!
                as Map)['id']
            as String;
    tv = insertDevice(server).id;
    groupId =
        (jsonBody(
                  await server.post(
                    '/api/v1/groups',
                    json: {'name': 'Salão'},
                    headers: admin,
                  ),
                )!
                as Map)['id']
            as int;
  });

  Future<http.Response> send(String method, String path, [Object? json]) =>
      server.send(method, '/api/v1/schedules$path', json: json, headers: admin);

  Map<String, Object?> body({Map<String, Object?> override = const {}}) => {
    'name': 'Almoço',
    'playlistId': playlistId,
    'groupId': groupId,
    'days': [1, 2, 3, 4, 5],
    'start': '11:00',
    'end': '14:00',
    'priority': 10,
    ...override,
  };

  Future<Map<Object?, Object?>> create([
    Map<String, Object?> override = const {},
  ]) async {
    final r = await send('POST', '', body(override: override));
    expect(r.statusCode, 201, reason: r.body);
    return jsonBody(r)! as Map;
  }

  test('exige sessão', () async {
    expect((await server.get('/api/v1/schedules')).statusCode, 401);
    expect((await server.post('/api/v1/schedules', json: {})).statusCode, 401);
    for (final m in ['GET', 'PATCH', 'DELETE']) {
      expect((await server.send(m, '/api/v1/schedules/x')).statusCode, 401);
    }
  });

  test('cria, lê, altera, lista e apaga', () async {
    final created = await create({
      'days': [5, 1, 3],
    });

    expect(created['name'], 'Almoço');
    expect(created['playlistId'], playlistId);
    expect(created['deviceId'], isNull);
    expect(created['groupId'], groupId);
    expect(created['days'], [1, 3, 5]);
    expect(created['start'], '11:00');
    expect(created['end'], '14:00');
    expect(created['priority'], 10);
    expect(DateTime.parse(created['createdAt'] as String).isUtc, isTrue);
    final id = created['id'] as String;

    expect(jsonBody(await send('GET', '/$id')), created);

    final patched = await send('PATCH', '/$id', {
      'name': '  Jantar ',
      'start': '19:30',
      'priority': 0,
    });
    expect(patched.statusCode, 200);
    final after = jsonBody(patched)! as Map;
    expect(after['name'], 'Jantar');
    expect(after['start'], '19:30');
    expect(after['end'], '14:00');
    expect(after['days'], [1, 3, 5]);
    expect(after['priority'], 0);
    expect(after['createdAt'], created['createdAt']);

    final list = (jsonBody(await send('GET', ''))! as Map)['schedules'] as List;
    expect(list, hasLength(1));

    expect((await send('DELETE', '/$id')).statusCode, 204);
    expect((await send('DELETE', '/$id')).statusCode, 404);
    expect((await send('GET', '/$id')).statusCode, 404);
    expect((await send('PATCH', '/$id', {'name': 'x'})).statusCode, 404);
  });

  test('aceita faixa que vira a noite e 24 horas', () async {
    final night = await create({'start': '22:00', 'end': '06:00'});
    expect(night['end'], '06:00');
    final all = await create({'start': '08:00', 'end': '08:00'});
    expect(all['start'], all['end']);
  });

  Future<void> expectError(
    Map<String, Object?> override,
    int status,
    String code,
  ) async {
    final r = await send('POST', '', body(override: override));
    expect(r.statusCode, status, reason: '$override');
    expect(errorCode(r), code, reason: '$override');
  }

  test('erros de validação', () async {
    await expectError({'name': ''}, 400, 'bad_request');
    await expectError({'name': 'a' * 65}, 400, 'bad_request');
    await expectError({'name': 7}, 400, 'bad_request');

    await expectError({'playlistId': 'nada'}, 400, 'unknown_playlist');
    await expectError({'playlistId': null}, 400, 'unknown_playlist');

    await expectError({'deviceId': tv}, 400, 'bad_request');
    await expectError({'groupId': null}, 400, 'bad_request');
    await expectError(
      {'groupId': null, 'deviceId': 'nada'},
      400,
      'unknown_device',
    );
    await expectError({'groupId': 999}, 400, 'unknown_group');

    for (final days in [
      <Object?>[],
      [0],
      [8],
      [1, 1],
      ['1'],
      'x',
      null,
    ]) {
      await expectError({'days': days}, 400, 'invalid_days');
    }

    for (final time in ['24:00', '9:00', '11:60', 'x', 660, null]) {
      await expectError({'start': time}, 400, 'invalid_time');
      await expectError({'end': time}, 400, 'invalid_time');
    }

    for (final priority in [-1, 101, 1.5, '10', null]) {
      await expectError({'priority': priority}, 400, 'invalid_priority');
    }
  });

  test('cria para uma TV', () async {
    final r = await create({'groupId': null, 'deviceId': tv});

    expect(r['deviceId'], tv);
    expect(r['groupId'], isNull);
  });

  test('PATCH revalida o resultado final', () async {
    final id = (await create())['id'] as String;

    for (final (patch, code) in [
      ({'days': <int>[]}, 'invalid_days'),
      ({'end': '25:00'}, 'invalid_time'),
      ({'priority': 200}, 'invalid_priority'),
      ({'playlistId': 'nada'}, 'unknown_playlist'),
      ({'groupId': 999}, 'unknown_group'),
      ({'deviceId': 'nada'}, 'unknown_device'),
      ({'groupId': null}, 'bad_request'),
      ({'name': ''}, 'bad_request'),
    ]) {
      final r = await send('PATCH', '/$id', patch);
      expect(r.statusCode, 400, reason: '$patch');
      expect(errorCode(r), code, reason: '$patch');
    }
    expect((jsonBody(await send('GET', '/$id'))! as Map)['groupId'], groupId);
  });

  test('PATCH troca o alvo de grupo para TV', () async {
    final id = (await create())['id'] as String;

    final r = await send('PATCH', '/$id', {'deviceId': tv});

    final body = jsonBody(r)! as Map;
    expect(body['deviceId'], tv);
    expect(body['groupId'], isNull);
  });

  test('filtra pelo alvo direto', () async {
    await create({'name': 'do grupo'});
    await create({'name': 'da TV', 'groupId': null, 'deviceId': tv});

    Future<List<Object?>> names(String query) async => [
      for (final s
          in (jsonBody(await send('GET', query))! as Map)['schedules'] as List)
        (s as Map)['name'],
    ];

    expect(await names(''), ['da TV', 'do grupo']);
    expect(await names('?deviceId=$tv'), ['da TV']);
    expect(await names('?groupId=$groupId'), ['do grupo']);
    expect(await names('?groupId=999'), isEmpty);
    expect((await send('GET', '?groupId=x')).statusCode, 400);
  });

  test('apagar playlist, TV ou grupo apaga os agendamentos', () async {
    final byGroup = await create({'name': 'g'});
    final byTv = await create({'name': 't', 'groupId': null, 'deviceId': tv});

    await server.send('DELETE', '/api/v1/groups/$groupId', headers: admin);
    expect((await send('GET', '/${byGroup['id']}')).statusCode, 404);
    expect((await send('GET', '/${byTv['id']}')).statusCode, 200);

    await server.send('DELETE', '/api/v1/devices/$tv', headers: admin);
    expect((await send('GET', '/${byTv['id']}')).statusCode, 404);

    final again = (await send('POST', '', {
      ...body(),
      'groupId': null,
      'deviceId': insertDevice(server, name: 'outra').id,
    }));
    final id = (jsonBody(again)! as Map)['id'];
    await server.send(
      'DELETE',
      '/api/v1/playlists/$playlistId',
      headers: admin,
    );
    expect((await send('GET', '/$id')).statusCode, 404);
  });
}
