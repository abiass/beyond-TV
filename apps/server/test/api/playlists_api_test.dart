import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/media_support.dart';
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
      server.send(method, '/api/v1/playlists$path', json: json, headers: admin);

  Future<String> createPlaylist([String name = 'Recepção']) async =>
      ((jsonBody(await send('POST', '', {'name': name}))!) as Map)['id']
          as String;

  Future<String> createSite([String url = 'https://a.local']) async {
    final r = await server.post(
      '/api/v1/media',
      json: {'kind': 'url', 'url': url},
      headers: admin,
    );
    return (jsonBody(r)! as Map)['id'] as String;
  }

  Future<String> createImage([int seed = 1]) async =>
      ((jsonBody(await uploadFile(server, admin, pngBytes(seed)))!)
              as Map)['id']
          as String;

  test('exige sessão', () async {
    expect((await server.get('/api/v1/playlists')).statusCode, 401);
    expect((await server.post('/api/v1/playlists', json: {})).statusCode, 401);
    for (final m in ['GET', 'PATCH', 'DELETE']) {
      expect((await server.send(m, '/api/v1/playlists/x')).statusCode, 401);
    }
    expect(
      (await server.send('PUT', '/api/v1/playlists/x/items')).statusCode,
      401,
    );
  });

  test('cria, lê, renomeia, lista e apaga', () async {
    final created = await send('POST', '', {'name': '  Manhã '});
    expect(created.statusCode, 201);
    final body = jsonBody(created)! as Map;
    expect(body['name'], 'Manhã');
    expect(body['items'], isEmpty);
    expect(DateTime.parse(body['createdAt'] as String).isUtc, isTrue);
    final id = body['id'] as String;

    expect((jsonBody(await send('GET', '/$id'))! as Map)['name'], 'Manhã');

    final renamed = await send('PATCH', '/$id', {'name': 'Tarde'});
    expect(renamed.statusCode, 200);
    expect((jsonBody(renamed)! as Map)['name'], 'Tarde');

    await createPlaylist('Aaa');
    final list = (jsonBody(await send('GET', ''))! as Map)['playlists'] as List;
    expect([for (final p in list) (p as Map)['name']], ['Aaa', 'Tarde']);
    expect(
      (list.first as Map).keys,
      containsAll(['id', 'name', 'itemCount', 'createdAt']),
    );
    expect((list.first as Map).containsKey('items'), isFalse);

    expect((await send('DELETE', '/$id')).statusCode, 204);
    expect((await send('GET', '/$id')).statusCode, 404);
    expect((await send('DELETE', '/$id')).statusCode, 404);
  });

  test('valida o nome', () async {
    expect((await send('POST', '', {})).statusCode, 400);
    expect((await send('POST', '', {'name': '   '})).statusCode, 400);
    expect((await send('POST', '', {'name': 'a' * 65})).statusCode, 400);
    final id = await createPlaylist();
    expect((await send('PATCH', '/$id', {'name': ''})).statusCode, 400);
    expect((await send('PATCH', '/nada', {'name': 'x'})).statusCode, 404);
  });

  test('PUT items preserva a ordem, os duplicados e as durações', () async {
    final id = await createPlaylist();
    final site = await createSite();
    final image = await createImage();

    final r = await send('PUT', '/$id/items', {
      'items': [
        {'mediaId': image, 'durationSeconds': 15},
        {'mediaId': site},
        {'mediaId': image, 'durationSeconds': null},
      ],
    });

    expect(r.statusCode, 200);
    final items = (jsonBody(r)! as Map)['items'] as List;
    expect(
      [for (final i in items) ((i as Map)['media'] as Map)['id']],
      [image, site, image],
    );
    expect(
      [for (final i in items) (i as Map)['durationSeconds']],
      [15, null, null],
    );
    expect(((items.first as Map)['media'] as Map)['sha256'], isNotNull);
    final list = (jsonBody(await send('GET', ''))! as Map)['playlists'] as List;
    expect((list.single as Map)['itemCount'], 3);

    final cleared = await send('PUT', '/$id/items', {'items': []});
    expect((jsonBody(cleared)! as Map)['items'], isEmpty);
  });

  test('PUT items valida o corpo', () async {
    final id = await createPlaylist();
    final site = await createSite();

    Future<http.Response> put(Object? items) =>
        send('PUT', '/$id/items', {'items': items});

    expect((await send('PUT', '/$id/items', {})).statusCode, 400);
    expect((await put('x')).statusCode, 400);
    expect((await put([1])).statusCode, 400);

    final unknown = await put([
      {'mediaId': 'nada'},
    ]);
    expect(unknown.statusCode, 400);
    expect(errorCode(unknown), 'unknown_media');
    expect(errorCode(await put([{}])), 'unknown_media');

    for (final d in [4, 86401, 1.5, '10']) {
      final r = await put([
        {'mediaId': site, 'durationSeconds': d},
      ]);
      expect(r.statusCode, 400, reason: '$d');
      expect(errorCode(r), 'invalid_duration');
    }
    for (final d in [5, 86400]) {
      expect(
        (await put([
          {'mediaId': site, 'durationSeconds': d},
        ])).statusCode,
        200,
      );
    }

    expect((await send('PUT', '/nada/items', {'items': []})).statusCode, 404);
  });

  test('limite de $maxPlaylistItems itens', () async {
    final id = await createPlaylist();
    final site = await createSite();
    Future<http.Response> put(int n) => send('PUT', '/$id/items', {
      'items': List.filled(n, {'mediaId': site}),
    });

    expect((await put(maxPlaylistItems)).statusCode, 200);
    final over = await put(maxPlaylistItems + 1);
    expect(over.statusCode, 400);
    expect(errorCode(over), 'bad_request');
  });

  test('apagar a mídia a remove da playlist', () async {
    final id = await createPlaylist();
    final a = await createSite('https://a.local');
    final b = await createSite('https://b.local');
    await send('PUT', '/$id/items', {
      'items': [
        {'mediaId': a},
        {'mediaId': b},
      ],
    });

    await server.send('DELETE', '/api/v1/media/$a', headers: admin);

    final items =
        (jsonBody(await send('GET', '/$id'))! as Map)['items'] as List;
    expect(items, hasLength(1));
    expect(((items.single as Map)['media'] as Map)['id'], b);
  });

  group('tempo real', () {
    late ({String id, String token}) tv;
    late Inbox tvInbox;
    late Inbox adminInbox;
    late String playlistId;
    late String siteId;
    late String imageId;

    ContentManifest manifestOf(Envelope e) =>
        ContentManifest.fromJson(e.payload);

    setUp(() async {
      tv = insertDevice(server);
      final channel = await connectDevice(server, tv.token);
      tvInbox = Inbox(channel);
      sendHello(channel);
      await tvInbox.nextOfType(MessageTypes.contentSync);
      adminInbox = Inbox(await connectAdmin(server, admin));
      playlistId = await createPlaylist();
      siteId = await createSite();
      imageId = await createImage();
      await send('PUT', '/$playlistId/items', {
        'items': [
          {'mediaId': siteId, 'durationSeconds': 20},
          {'mediaId': imageId},
        ],
      });
    });

    Future<http.Response> assign() => server.send(
      'PUT',
      '/api/v1/devices/${tv.id}/content',
      json: {'playlistId': playlistId},
      headers: admin,
    );

    test('atribuir manda os itens da playlist e o resumo', () async {
      final r = await assign();

      final body = jsonBody(r)! as Map;
      expect(body['playlist'], {'id': playlistId, 'name': 'Recepção'});
      expect(body['content'], isNull);
      final items = manifestOf(
        await tvInbox.nextOfType(MessageTypes.contentSync),
      ).items;
      expect([for (final i in items) i.mediaId], [siteId, imageId]);
      expect(items.first.durationSeconds, 20);
      expect(items.first.url, 'https://a.local');
      expect(items.last.sha256, isNotNull);
      expect(items.last.url, isNull);
    });

    test('trocar os itens manda novo manifesto', () async {
      await assign();
      await tvInbox.nextOfType(MessageTypes.contentSync);

      await send('PUT', '/$playlistId/items', {
        'items': [
          {'mediaId': imageId},
          {'mediaId': imageId},
          {'mediaId': siteId},
        ],
      });

      final items = manifestOf(
        await tvInbox.nextOfType(MessageTypes.contentSync),
      ).items;
      expect([for (final i in items) i.mediaId], [imageId, imageId, siteId]);
    });

    test('apagar mídia contida atualiza a TV', () async {
      await assign();
      await tvInbox.nextOfType(MessageTypes.contentSync);

      await server.send('DELETE', '/api/v1/media/$siteId', headers: admin);

      final items = manifestOf(
        await tvInbox.nextOfType(MessageTypes.contentSync),
      ).items;
      expect([for (final i in items) i.mediaId], [imageId]);
    });

    test('renomear mídia contida atualiza a TV', () async {
      await assign();
      await tvInbox.nextOfType(MessageTypes.contentSync);

      await server.send(
        'PATCH',
        '/api/v1/media/$imageId',
        json: {'name': 'Novo nome'},
        headers: admin,
      );

      final items = manifestOf(
        await tvInbox.nextOfType(MessageTypes.contentSync),
      ).items;
      expect(items.last.name, 'Novo nome');
    });

    test('apagar a playlist esvazia a TV e avisa o painel', () async {
      await assign();
      await tvInbox.nextOfType(MessageTypes.contentSync);

      expect((await send('DELETE', '/$playlistId')).statusCode, 204);

      expect(
        manifestOf(await tvInbox.nextOfType(MessageTypes.contentSync)).isEmpty,
        isTrue,
      );
      var state = await adminInbox.nextOfType(MessageTypes.deviceState);
      while (state.payload['playlist'] != null) {
        state = await adminInbox.nextOfType(MessageTypes.deviceState);
      }
      expect(state.payload['content'], isNull);
    });

    test('renomear não manda content.sync mas avisa o painel', () async {
      await assign();
      await tvInbox.nextOfType(MessageTypes.contentSync);

      await send('PATCH', '/$playlistId', {'name': 'Nova'});

      var state = await adminInbox.nextOfType(MessageTypes.deviceState);
      while ((state.payload['playlist'] as Map?)?['name'] != 'Nova') {
        state = await adminInbox.nextOfType(MessageTypes.deviceState);
      }
      await expectLater(
        tvInbox.nextOfType(MessageTypes.contentSync),
        throwsA(isA<Exception>()),
      );
    });
  });
}
