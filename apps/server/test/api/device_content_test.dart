import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/realtime_support.dart';
import '../support/test_server.dart';

void main() {
  late TestServer server;
  late Map<String, String> admin;
  late ({String id, String token}) tv;
  late Inbox tvInbox;

  setUp(() async {
    server = await TestServer.start();
    admin = await setupAdmin(server);
    tv = insertDevice(server);
  });

  Future<void> connectTv() async {
    final channel = await connectDevice(server, tv.token);
    tvInbox = Inbox(channel);
    sendHello(channel);
    final first = await tvInbox.nextOfType(MessageTypes.contentSync);
    expect(first.payload['items'], isEmpty);
  }

  Future<http.Response> put(Object body) => server.send(
    'PUT',
    '/api/v1/devices/${tv.id}/content',
    json: body,
    headers: admin,
  );

  ContentManifest manifestOf(Envelope e) => ContentManifest.fromJson(e.payload);

  Future<List<Object?>> mediaList() async =>
      (jsonBody(await server.get('/api/v1/media', headers: admin))!
              as Map)['media']
          as List<Object?>;

  test('PUT com url devolve content e manda content.sync', () async {
    await connectTv();

    final r = await put({'url': 'https://a.local/x'});

    expect(r.statusCode, 200);
    final body = jsonBody(r)! as Map;
    expect((body['content'] as Map)['url'], 'https://a.local/x');
    final sync = await tvInbox.nextOfType(MessageTypes.contentSync);
    final manifest = manifestOf(sync);
    expect(manifest.items, hasLength(1));
    expect(
      manifest.revision,
      ContentManifest(
        items: [
          ContentItem.fromJson(
            (body['content'] as Map).cast<String, Object?>(),
          ),
        ],
      ).revision,
    );
  });

  test('PUT com a mesma URL reaproveita a mídia', () async {
    await put({'url': 'https://a.local/x'});
    await put({'url': 'https://a.local/x'});

    expect(await mediaList(), hasLength(1));
  });

  test('PUT valida o corpo', () async {
    expect((await put({})).statusCode, 400);
    expect(
      (await put({'mediaId': null, 'url': 'https://a.local'})).statusCode,
      400,
    );
    expect((await put({'url': 'ftp://x'})).statusCode, 400);
    expect((await put({'mediaId': 'nada'})).statusCode, 404);
    final missing = await server.send(
      'PUT',
      '/api/v1/devices/nada/content',
      json: {'mediaId': null},
      headers: admin,
    );
    expect(missing.statusCode, 404);
  });

  test('mediaId nulo limpa e manda manifesto vazio', () async {
    await connectTv();
    await put({'url': 'https://a.local'});
    await tvInbox.nextOfType(MessageTypes.contentSync);

    final r = await put({'mediaId': null});

    expect(r.statusCode, 200);
    expect((jsonBody(r)! as Map)['content'], isNull);
    final sync = await tvInbox.nextOfType(MessageTypes.contentSync);
    expect(manifestOf(sync).isEmpty, isTrue);
  });

  test('PATCH da URL gera manifesto novo', () async {
    await connectTv();
    final r = await put({'url': 'https://a.local'});
    final mediaId = ((jsonBody(r)! as Map)['content'] as Map)['mediaId'];
    final before = manifestOf(
      await tvInbox.nextOfType(MessageTypes.contentSync),
    );

    await server.send(
      'PATCH',
      '/api/v1/media/$mediaId',
      json: {'url': 'https://b.local'},
      headers: admin,
    );

    final after = manifestOf(
      await tvInbox.nextOfType(MessageTypes.contentSync),
    );
    expect(after.revision, isNot(before.revision));
    expect(after.items.single.url, 'https://b.local');
  });

  test('DELETE da mídia esvazia a TV', () async {
    await connectTv();
    final r = await put({'url': 'https://a.local'});
    final mediaId = ((jsonBody(r)! as Map)['content'] as Map)['mediaId'];
    await tvInbox.nextOfType(MessageTypes.contentSync);

    await server.send('DELETE', '/api/v1/media/$mediaId', headers: admin);

    final sync = await tvInbox.nextOfType(MessageTypes.contentSync);
    expect(manifestOf(sync).isEmpty, isTrue);
    final list =
        jsonBody(await server.get('/api/v1/devices', headers: admin))! as Map;
    expect(((list['devices'] as List).single as Map)['content'], isNull);
  });

  test('hello recebe o conteúdo atual', () async {
    await put({'url': 'https://a.local'});

    final channel = await connectDevice(server, tv.token);
    final inbox = Inbox(channel);
    sendHello(channel);

    final sync = await inbox.nextOfType(MessageTypes.contentSync);
    expect(manifestOf(sync).items.single.url, 'https://a.local');
  });

  test('device.state chega ao admin com content', () async {
    final adminInbox = Inbox(await connectAdmin(server, admin));

    await put({'url': 'https://a.local'});

    final event = await adminInbox.nextOfType(MessageTypes.deviceState);
    expect((event.payload['content'] as Map)['url'], 'https://a.local');
  });

  group('playlist', () {
    Future<String> createPlaylist() async =>
        (jsonBody(
                  await server.post(
                    '/api/v1/playlists',
                    json: {'name': 'Lista'},
                    headers: admin,
                  ),
                )!
                as Map)['id']
            as String;

    test('playlistId inexistente dá 404', () async {
      expect((await put({'playlistId': 'nada'})).statusCode, 404);
    });

    test('duas chaves dão 400', () async {
      final id = await createPlaylist();

      expect((await put({'playlistId': id, 'mediaId': null})).statusCode, 400);
      expect(
        (await put({'playlistId': id, 'url': 'https://a.local'})).statusCode,
        400,
      );
      expect((await put({'playlistId': 5})).statusCode, 400);
    });

    test('atribuir playlist limpa a mídia avulsa e vice-versa', () async {
      final id = await createPlaylist();
      await put({'url': 'https://a.local'});

      final withPlaylist = jsonBody(await put({'playlistId': id}))! as Map;
      expect(withPlaylist['content'], isNull);
      expect(withPlaylist['playlist'], {'id': id, 'name': 'Lista'});

      final withMedia = jsonBody(await put({'url': 'https://b.local'}))! as Map;
      expect((withMedia['content'] as Map)['url'], 'https://b.local');
      expect(withMedia['playlist'], isNull);
    });

    test('playlistId nulo limpa e manda manifesto vazio', () async {
      final id = await createPlaylist();
      // Playlist vazia não mudaria o manifesto (e o revision só muda com
      // conteúdo), então ela precisa de um item.
      final media =
          jsonBody(
                await server.post(
                  '/api/v1/media',
                  json: {
                    'kind': 'url',
                    'url': 'https://a.local/p',
                    'name': 'P',
                  },
                  headers: admin,
                ),
              )!
              as Map;
      await server.send(
        'PUT',
        '/api/v1/playlists/$id/items',
        json: {
          'items': [
            {'mediaId': media['id']},
          ],
        },
        headers: admin,
      );
      await connectTv();
      await put({'playlistId': id});
      await tvInbox.nextOfType(MessageTypes.contentSync);

      final r = await put({'playlistId': null});

      expect(r.statusCode, 200);
      expect((jsonBody(r)! as Map)['playlist'], isNull);
      final sync = await tvInbox.nextOfType(MessageTypes.contentSync);
      expect(manifestOf(sync).isEmpty, isTrue);
    });

    test('a listagem de TVs traz a playlist', () async {
      final id = await createPlaylist();
      await put({'playlistId': id});

      final list =
          jsonBody(await server.get('/api/v1/devices', headers: admin))! as Map;

      final device = (list['devices'] as List).single as Map;
      expect(device['playlist'], {'id': id, 'name': 'Lista'});
      expect(device['content'], isNull);
    });

    test('hello recebe os itens da playlist atual', () async {
      final id = await createPlaylist();
      final media = await server.post(
        '/api/v1/media',
        json: {'kind': 'url', 'url': 'https://a.local'},
        headers: admin,
      );
      await server.send(
        'PUT',
        '/api/v1/playlists/$id/items',
        json: {
          'items': [
            {'mediaId': (jsonBody(media)! as Map)['id']},
          ],
        },
        headers: admin,
      );
      await put({'playlistId': id});

      final channel = await connectDevice(server, tv.token);
      final inbox = Inbox(channel);
      sendHello(channel);

      final sync = await inbox.nextOfType(MessageTypes.contentSync);
      expect(manifestOf(sync).items.single.url, 'https://a.local');
    });
  });
}
