import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
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

  File fileOf(String sha256) => File(p.join(server.mediaDir, sha256));

  Future<Map<String, Object?>> upload(
    List<int> bytes, {
    String mime = 'image/png',
    String? name,
  }) async =>
      jsonBody(await uploadFile(server, admin, bytes, mime: mime, name: name))!
          as Map<String, Object?>;

  test('upload exige admin', () async {
    final r = await uploadFile(server, {}, pngBytes());

    expect(r.statusCode, 401);
  });

  test('upload responde 201 com o JSON do contrato', () async {
    final bytes = pngBytes();

    final r = await uploadFile(server, admin, bytes, name: ' Promoção ');

    expect(r.statusCode, 201);
    final body = jsonBody(r)! as Map;
    expect(body['kind'], 'image');
    expect(body['name'], 'Promoção');
    expect(body['sha256'], sha256.convert(bytes).toString());
    expect(body['sizeBytes'], bytes.length);
    expect(body['mime'], 'image/png');
    expect(body.containsKey('url'), isFalse);
    expect(DateTime.parse(body['createdAt'] as String).isUtc, isTrue);
    expect(fileOf(body['sha256'] as String).readAsBytesSync(), bytes);
  });

  test('nome padrão é Imagem ou Vídeo', () async {
    expect((await upload(pngBytes()))['name'], 'Imagem');
    expect((await upload(mp4Bytes(), mime: 'video/mp4'))['name'], 'Vídeo');
  });

  test('nome inválido dá 400', () async {
    final r = await uploadFile(server, admin, pngBytes(), name: 'a' * 65);

    expect(r.statusCode, 400);
    expect(errorCode(r), 'bad_request');
  });

  test('upload repetido responde 200 com a mesma mídia', () async {
    final first = await uploadFile(server, admin, pngBytes(), name: 'A');
    final second = await uploadFile(server, admin, pngBytes(), name: 'B');

    expect(first.statusCode, 201);
    expect(second.statusCode, 200);
    expect((jsonBody(second)! as Map)['id'], (jsonBody(first)! as Map)['id']);
    expect((jsonBody(second)! as Map)['name'], 'A');
    final list = jsonBody(await server.get('/api/v1/media', headers: admin))!;
    expect((list as Map)['media'], hasLength(1));
  });

  test('erros de validação do upload', () async {
    final wrongMime = await uploadFile(
      server,
      admin,
      pngBytes(),
      mime: 'image/jpeg',
    );
    final badType = await uploadFile(
      server,
      admin,
      pngBytes(),
      mime: 'text/html',
    );
    final empty = await uploadFile(server, admin, []);

    expect(wrongMime.statusCode, 415);
    expect(errorCode(wrongMime), 'unsupported_media_type');
    expect(badType.statusCode, 415);
    expect(empty.statusCode, 400);
    expect(Directory(p.join(server.mediaDir, 'tmp')).listSync(), isEmpty);
  });

  test('imagem acima de 25 MiB dá 413 pelo Content-Length', () async {
    // Socket cru para mandar um Content-Length enorme; o corpo (zeros) é
    // enviado aos poucos e o servidor o descarta sem guardar.
    final socket = await Socket.connect(
      server.uri('/').host,
      server.uri('/').port,
    );
    addTearDown(socket.destroy);
    socket.write(
      'POST /api/v1/media/files HTTP/1.1\r\n'
      'Host: localhost\r\n'
      'Content-Type: image/png\r\n'
      'Content-Length: ${25 * 1024 * 1024 + 1}\r\n'
      'Cookie: ${admin['cookie']}\r\n\r\n',
    );
    final head = socket
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .first;
    final chunk = Uint8List(1024 * 1024);
    for (var i = 0; i < 26; i++) {
      socket.add(chunk);
      await socket.flush();
    }

    final response = await head.timeout(const Duration(seconds: 10));
    expect(response, startsWith('HTTP/1.1 413'));
    expect(response, contains('payload_too_large'));
  });

  group('download', () {
    late Map<String, Object?> media;
    late List<int> bytes;

    setUp(() async {
      bytes = pngBytes();
      media = await upload(bytes);
    });

    String path() => '/api/v1/media/${media['id']}/file';

    test('com cookie de admin devolve o arquivo e os cabeçalhos', () async {
      final r = await server.get(path(), headers: admin);

      expect(r.statusCode, 200);
      expect(r.bodyBytes, bytes);
      expect(r.headers['content-type'], 'image/png');
      expect(r.headers['content-length'], '${bytes.length}');
      expect(r.headers['etag'], '"${media['sha256']}"');
      expect(r.headers['x-content-type-options'], 'nosniff');
      expect(
        r.headers['cache-control'],
        'private, max-age=31536000, immutable',
      );
    });

    test('com Bearer de TV pareada', () async {
      final tv = insertDevice(server);

      final r = await server.get(
        path(),
        headers: {'authorization': 'Bearer ${tv.token}'},
      );

      expect(r.statusCode, 200);
      expect(r.bodyBytes, bytes);
    });

    test('sem auth ou com token errado dá 401', () async {
      insertDevice(server);

      expect((await server.get(path())).statusCode, 401);
      expect(
        (await server.get(
          path(),
          headers: {'authorization': 'Bearer errado'},
        )).statusCode,
        401,
      );
      expect(
        (await server.get(
          path(),
          headers: {'cookie': 'beyond_session=x'},
        )).statusCode,
        401,
      );
    });

    test('If-None-Match igual responde 304 sem corpo', () async {
      final r = await server.get(
        path(),
        headers: {...admin, 'if-none-match': '"${media['sha256']}"'},
      );

      expect(r.statusCode, 304);
      expect(r.bodyBytes, isEmpty);
      expect(r.headers['etag'], '"${media['sha256']}"');
    });

    test('If-None-Match diferente devolve o arquivo', () async {
      final r = await server.get(
        path(),
        headers: {...admin, 'if-none-match': '"outro"'},
      );

      expect(r.statusCode, 200);
    });

    test('mídia inexistente ou de site dá 404', () async {
      final site = await server.post(
        '/api/v1/media',
        json: {'kind': 'url', 'url': 'https://a.local'},
        headers: admin,
      );
      final siteId = (jsonBody(site)! as Map)['id'];

      expect(
        (await server.get(
          '/api/v1/media/nada/file',
          headers: admin,
        )).statusCode,
        404,
      );
      expect(
        (await server.get(
          '/api/v1/media/$siteId/file',
          headers: admin,
        )).statusCode,
        404,
      );
    });
  });

  test('PATCH de arquivo só aceita o nome', () async {
    final media = await upload(pngBytes());
    final id = media['id'];

    final ok = await server.send(
      'PATCH',
      '/api/v1/media/$id',
      json: {'name': 'Novo'},
      headers: admin,
    );
    final withUrl = await server.send(
      'PATCH',
      '/api/v1/media/$id',
      json: {'url': 'https://a.local'},
      headers: admin,
    );

    expect(ok.statusCode, 200);
    expect((jsonBody(ok)! as Map)['name'], 'Novo');
    expect((jsonBody(ok)! as Map)['sha256'], media['sha256']);
    expect(withUrl.statusCode, 400);
  });

  test('DELETE apaga o arquivo só quando ninguém mais usa o hash', () async {
    final media = await upload(pngBytes());
    final sha = media['sha256'] as String;
    // Segunda mídia com o mesmo hash, criada direto no banco.
    server.db.execute(
      'INSERT INTO media (id, kind, name, sha256, size_bytes, mime) '
      "VALUES ('dup', 'image', 'Dup', ?, 1, 'image/png')",
      [sha],
    );

    final first = await server.send(
      'DELETE',
      '/api/v1/media/${media['id']}',
      headers: admin,
    );
    expect(first.statusCode, 204);
    expect(fileOf(sha).existsSync(), isTrue);

    final second = await server.send(
      'DELETE',
      '/api/v1/media/dup',
      headers: admin,
    );
    expect(second.statusCode, 204);
    expect(fileOf(sha).existsSync(), isFalse);
  });
}
