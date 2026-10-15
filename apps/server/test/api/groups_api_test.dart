import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:http/http.dart' as http;
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

  Future<http.Response> send(String method, String path, [Object? json]) =>
      server.send(method, '/api/v1/groups$path', json: json, headers: admin);

  Future<Map<Object?, Object?>> createGroup([String name = 'Recepção']) async =>
      jsonBody(await send('POST', '', {'name': name}))! as Map;

  Future<String> createPlaylist() async =>
      (jsonBody(
                await server.post(
                  '/api/v1/playlists',
                  json: {'name': 'Manhã'},
                  headers: admin,
                ),
              )!
              as Map)['id']
          as String;

  Future<Map<Object?, Object?>> deviceOf(String id) async {
    final list =
        jsonBody(await server.get('/api/v1/devices', headers: admin))! as Map;
    return (list['devices'] as List).cast<Map<Object?, Object?>>().firstWhere(
      (d) => d['id'] == id,
    );
  }

  test('exige sessão', () async {
    expect((await server.get('/api/v1/groups')).statusCode, 401);
    expect((await server.post('/api/v1/groups', json: {})).statusCode, 401);
    for (final m in ['PATCH', 'DELETE']) {
      expect((await server.send(m, '/api/v1/groups/1')).statusCode, 401);
    }
    for (final path in ['devices', 'content']) {
      expect(
        (await server.send('PUT', '/api/v1/groups/1/$path')).statusCode,
        401,
      );
    }
  });

  test('cria, lista por nome, renomeia e apaga', () async {
    final created = await send('POST', '', {'name': '  Recepção '});
    expect(created.statusCode, 201);
    final body = jsonBody(created)! as Map;
    expect(body['name'], 'Recepção');
    expect(body['deviceIds'], isEmpty);
    expect(body['content'], isNull);
    expect(body['playlist'], isNull);
    expect(DateTime.parse(body['createdAt'] as String).isUtc, isTrue);
    final id = body['id'] as int;
    await createGroup('Armazém');

    final list = (jsonBody(await send('GET', ''))! as Map)['groups'] as List;
    expect([for (final g in list) (g as Map)['name']], ['Armazém', 'Recepção']);

    final renamed = await send('PATCH', '/$id', {'name': 'Hall'});
    expect(renamed.statusCode, 200);
    expect((jsonBody(renamed)! as Map)['name'], 'Hall');

    expect((await send('DELETE', '/$id')).statusCode, 204);
    expect((await send('DELETE', '/$id')).statusCode, 404);
    expect((await send('PATCH', '/$id', {'name': 'x'})).statusCode, 404);
    expect((await send('DELETE', '/abc')).statusCode, 404);
  });

  test('valida o nome', () async {
    for (final name in [null, 42, '', '   ', 'a' * 65]) {
      final r = await send('POST', '', {'name': name});
      expect(r.statusCode, 400, reason: '$name');
      expect(errorCode(r), 'bad_request');
    }
  });

  test('nome repetido com outra caixa dá 409 name_taken', () async {
    final first = await createGroup('Recepcao');

    final dup = await send('POST', '', {'name': 'RECEPCAO'});
    expect(dup.statusCode, 409);
    expect(errorCode(dup), 'name_taken');

    final other = await createGroup('Hall');
    final clash = await send('PATCH', '/${other['id']}', {'name': 'recepcao'});
    expect(clash.statusCode, 409);
    expect(errorCode(clash), 'name_taken');

    final same = await send('PATCH', '/${first['id']}', {'name': 'RECEPCAO'});
    expect(same.statusCode, 200);
  });

  test('PUT devices move TVs entre grupos e tira as que saíram', () async {
    final tv1 = insertDevice(server, name: 'um').id;
    final tv2 = insertDevice(server, name: 'dois').id;
    final tv3 = insertDevice(server, name: 'tres').id;
    final a = (await createGroup('A'))['id'] as int;
    final b = (await createGroup('B'))['id'] as int;

    final first = await send('PUT', '/$a/devices', {
      'deviceIds': [tv1, tv2],
    });
    expect(first.statusCode, 200);
    expect(((jsonBody(first)! as Map)['deviceIds'] as List).toSet(), {
      tv1,
      tv2,
    });

    final second = await send('PUT', '/$b/devices', {
      'deviceIds': [tv2, tv3],
    });
    expect(((jsonBody(second)! as Map)['deviceIds'] as List).toSet(), {
      tv2,
      tv3,
    });
    expect((await deviceOf(tv2))['groupId'], b);
    expect((await deviceOf(tv1))['groupId'], a);

    final listed = (jsonBody(await send('GET', ''))! as Map)['groups'] as List;
    expect((listed.first as Map)['deviceIds'], [tv1]);

    await send('PUT', '/$b/devices', {'deviceIds': <String>[]});
    expect((await deviceOf(tv2))['groupId'], isNull);
    expect((await deviceOf(tv3))['groupId'], isNull);
  });

  test('PUT devices valida a lista', () async {
    final tv = insertDevice(server).id;
    final id = (await createGroup())['id'] as int;

    final unknown = await send('PUT', '/$id/devices', {
      'deviceIds': [tv, 'nada'],
    });
    expect(unknown.statusCode, 400);
    expect(errorCode(unknown), 'unknown_device');
    expect((await deviceOf(tv))['groupId'], isNull);

    for (final body in [
      <String, Object?>{},
      {'deviceIds': 'x'},
      {
        'deviceIds': [1],
      },
    ]) {
      final r = await send('PUT', '/$id/devices', body);
      expect(r.statusCode, 400);
      expect(errorCode(r), 'bad_request');
    }
    expect(
      (await send('PUT', '/999/devices', {'deviceIds': <String>[]})).statusCode,
      404,
    );
  });

  test('PUT content aceita url, playlist, mídia e limpa', () async {
    final id = (await createGroup())['id'] as int;

    final url = await send('PUT', '/$id/content', {
      'url': 'https://a.local/x',
      'name': 'X',
    });
    expect(url.statusCode, 200);
    final withUrl = jsonBody(url)! as Map;
    expect((withUrl['content'] as Map)['url'], 'https://a.local/x');
    expect(withUrl['playlist'], isNull);

    final playlistId = await createPlaylist();
    final withPlaylist =
        jsonBody(await send('PUT', '/$id/content', {'playlistId': playlistId}))!
            as Map;
    expect(withPlaylist['content'], isNull);
    expect(withPlaylist['playlist'], {'id': playlistId, 'name': 'Manhã'});

    final mediaId = (withUrl['content'] as Map)['mediaId'];
    final withMedia =
        jsonBody(await send('PUT', '/$id/content', {'mediaId': mediaId}))!
            as Map;
    expect((withMedia['content'] as Map)['mediaId'], mediaId);
    expect(withMedia['playlist'], isNull);

    final cleared =
        jsonBody(await send('PUT', '/$id/content', {'mediaId': null}))! as Map;
    expect(cleared['content'], isNull);
    expect(cleared['playlist'], isNull);
  });

  test('PUT content valida o corpo como o da TV', () async {
    final id = (await createGroup())['id'] as int;

    expect((await send('PUT', '/$id/content', {})).statusCode, 400);
    expect(
      (await send('PUT', '/$id/content', {
        'mediaId': null,
        'playlistId': null,
      })).statusCode,
      400,
    );
    final bad = await send('PUT', '/$id/content', {'url': 'ftp://x'});
    expect(bad.statusCode, 400);
    expect(errorCode(bad), 'invalid_url');
    expect(
      (await send('PUT', '/$id/content', {'mediaId': 'nada'})).statusCode,
      404,
    );
    expect(
      (await send('PUT', '/$id/content', {'playlistId': 'nada'})).statusCode,
      404,
    );
    expect(
      (await send('PUT', '/999/content', {'mediaId': null})).statusCode,
      404,
    );
  });

  test('apagar a playlist limpa o conteúdo do grupo', () async {
    final id = (await createGroup())['id'] as int;
    final playlistId = await createPlaylist();
    await send('PUT', '/$id/content', {'playlistId': playlistId});

    await server.send(
      'DELETE',
      '/api/v1/playlists/$playlistId',
      headers: admin,
    );

    final list = (jsonBody(await send('GET', ''))! as Map)['groups'] as List;
    expect((list.single as Map)['playlist'], isNull);
  });

  group('PATCH /devices/:id com groupId', () {
    late String tv;

    setUp(() => tv = insertDevice(server).id);

    Future<http.Response> patch(Object body) =>
        server.send('PATCH', '/api/v1/devices/$tv', json: body, headers: admin);

    test('põe e tira a TV do grupo', () async {
      final id = (await createGroup())['id'] as int;

      final into = await patch({'groupId': id});
      expect(into.statusCode, 200);
      final summary = jsonBody(into)! as Map;
      expect(summary['groupId'], id);
      expect(summary['name'], 'Recepção');
      final listed =
          (jsonBody(await send('GET', ''))! as Map)['groups'] as List;
      expect((listed.single as Map)['deviceIds'], [tv]);

      final out = await patch({'groupId': null});
      expect((jsonBody(out)! as Map)['groupId'], isNull);
    });

    test('aceita name e groupId juntos', () async {
      final id = (await createGroup())['id'] as int;

      final r = await patch({'name': 'Balcão', 'groupId': id});

      final summary = jsonBody(r)! as Map;
      expect(summary['name'], 'Balcão');
      expect(summary['groupId'], id);
    });

    test('grupo inexistente dá 400 unknown_group', () async {
      final r = await patch({'groupId': 999});
      expect(r.statusCode, 400);
      expect(errorCode(r), 'unknown_group');
      expect((await deviceOf(tv))['groupId'], isNull);
    });

    test('groupId inválido e corpo vazio dão 400', () async {
      expect((await patch({'groupId': 'x'})).statusCode, 400);
      expect((await patch(<String, Object?>{})).statusCode, 400);
    });
  });

  test('apagar o grupo zera o groupId das TVs e avisa o painel', () async {
    final tv = insertDevice(server).id;
    final id = (await createGroup())['id'] as int;
    await send('PUT', '/$id/devices', {
      'deviceIds': [tv],
    });
    final adminInbox = Inbox(await connectAdmin(server, admin));

    await send('DELETE', '/$id');

    final state = await adminInbox.nextOfType(MessageTypes.deviceState);
    expect(state.payload['id'], tv);
    expect(state.payload['groupId'], isNull);
    expect((await deviceOf(tv))['groupId'], isNull);
  });

  test('mudar os membros publica device.state das TVs afetadas', () async {
    final tv = insertDevice(server).id;
    final id = (await createGroup())['id'] as int;
    final adminInbox = Inbox(await connectAdmin(server, admin));

    await send('PUT', '/$id/devices', {
      'deviceIds': [tv],
    });

    final state = await adminInbox.nextOfType(MessageTypes.deviceState);
    expect(state.payload['id'], tv);
    expect(state.payload['groupId'], id);
  });
}
