import 'dart:convert';
import 'dart:typed_data';

import 'package:beyond_dashboard/src/api/api_client.dart';
import 'package:beyond_dashboard/src/api/media.dart';
import 'package:beyond_dashboard/src/api/playlists.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _imageJson = {
  'id': 'm1',
  'kind': 'image',
  'name': 'Promoção',
  'sha256': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
  'sizeBytes': 183422,
  'mime': 'image/png',
  'createdAt': '2026-10-01T10:00:00.000Z',
};
const _siteJson = {
  'id': 'm2',
  'kind': 'url',
  'name': 'Painel',
  'url': 'https://example.local/painel',
  'createdAt': '2026-10-01T10:00:00.000Z',
};

void main() {
  final base = Uri.parse('http://192.168.0.10:8787/');

  late http.Request sent;
  ApiClient clientWith(int status, Object? body) => ApiClient(
        client: MockClient((request) async {
          sent = request;
          return http.Response(body == null ? '' : jsonEncode(body), status);
        }),
        baseUri: base,
      );

  test('Media de arquivo traz sha256, tamanho e mime', () {
    final media = Media.fromJson(_imageJson);

    expect(media.isFile, isTrue);
    expect(media.isImage, isTrue);
    expect(media.sizeBytes, 183422);
    expect(media.mime, 'image/png');
    expect(media.sha256, startsWith('e3b0'));
    expect(media.url, isNull);
  });

  test('Media de site não é arquivo', () {
    final media = Media.fromJson(_siteJson);

    expect(media.isFile, isFalse);
    expect(media.isSite, isTrue);
    expect(media.sizeBytes, isNull);
  });

  test('Playlist e PlaylistSummary', () {
    final playlist = Playlist.fromJson({
      'id': 'p1',
      'name': 'Recepção manhã',
      'createdAt': '2026-10-01T10:00:00.000Z',
      'items': [
        {'media': _imageJson, 'durationSeconds': 15},
        {'media': _siteJson, 'durationSeconds': null},
      ],
    });

    expect(playlist.items, hasLength(2));
    expect(playlist.items[0].media.id, 'm1');
    expect(playlist.items[0].durationSeconds, 15);
    expect(playlist.items[1].durationSeconds, isNull);
    expect(playlist.summary.itemCount, 2);

    final summary = PlaylistSummary.fromJson({
      'id': 'p1',
      'name': 'Recepção manhã',
      'itemCount': 3,
      'createdAt': '2026-10-01T10:00:00.000Z',
    });
    expect(summary.itemCount, 3);
  });

  test('uploadMedia manda o corpo cru com o Content-Type e o nome', () async {
    final api = clientWith(201, _imageJson);
    final bytes = Uint8List.fromList([1, 2, 3, 255]);

    final media = await api.uploadMedia(
      bytes,
      mime: 'image/png',
      name: 'Cartaz & verão',
    );

    expect(media.id, 'm1');
    expect(sent.method, 'POST');
    expect(sent.url.path, '/api/v1/media/files');
    expect(sent.url.queryParameters, {'name': 'Cartaz & verão'});
    expect(sent.headers['content-type'], 'image/png');
    expect(sent.bodyBytes, bytes);
  });

  test('uploadMedia sem nome não manda o parâmetro', () async {
    final api = clientWith(200, _imageJson);

    await api.uploadMedia(Uint8List(1), mime: 'video/mp4');

    expect(sent.url.hasQuery, isFalse);
    expect(sent.headers['content-type'], 'video/mp4');
  });

  test('uploadMedia traduz 413 em ApiException', () {
    final api = clientWith(413, {
      'error': {'code': 'payload_too_large', 'message': 'Grande demais.'},
    });

    expect(
      () => api.uploadMedia(Uint8List(1), mime: 'image/png'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 413)
            .having((e) => e.code, 'code', 'payload_too_large'),
      ),
    );
  });

  test('fileUrl usa a origem do painel', () {
    final api = clientWith(200, null);

    expect(
      api.fileUrl('m1').toString(),
      'http://192.168.0.10:8787/api/v1/media/m1/file',
    );
  });

  test('setPlaylistItems manda a lista na ordem, omitindo duração nula',
      () async {
    final api = clientWith(200, {
      'id': 'p1',
      'name': 'x',
      'createdAt': '2026-10-01T10:00:00.000Z',
      'items': <Object?>[],
    });

    await api.setPlaylistItems('p1', [('b', 20), ('a', null)]);

    expect(sent.method, 'PUT');
    expect(sent.url.path, '/api/v1/playlists/p1/items');
    expect(jsonDecode(sent.body), {
      'items': [
        {'mediaId': 'b', 'durationSeconds': 20},
        {'mediaId': 'a'},
      ],
    });
  });

  test('setDevicePlaylist manda playlistId (ou null para limpar)', () async {
    final api = clientWith(200, {
      'id': 'd1',
      'name': 'TV',
      'online': false,
      'createdAt': '2026-10-01T10:00:00.000Z',
      'playlist': {'id': 'p1', 'name': 'Recepção'},
    });

    final device = await api.setDevicePlaylist('d1', 'p1');

    expect(sent.method, 'PUT');
    expect(sent.url.path, '/api/v1/devices/d1/content');
    expect(jsonDecode(sent.body), {'playlistId': 'p1'});
    expect(device.playlist?.name, 'Recepção');

    await api.setDevicePlaylist('d1', null);
    expect(jsonDecode(sent.body), {'playlistId': null});
  });

  test('renomear e apagar mídia e playlist usam as rotas do contrato',
      () async {
    final api = clientWith(204, null);

    await api.deleteMedia('m1');
    expect((sent.method, sent.url.path), ('DELETE', '/api/v1/media/m1'));
    await api.deletePlaylist('p1');
    expect((sent.method, sent.url.path), ('DELETE', '/api/v1/playlists/p1'));
  });
}
