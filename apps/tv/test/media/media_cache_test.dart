import 'dart:convert';
import 'dart:io';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_tv/src/media/media_cache.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _bytes = utf8.encode('conteúdo da imagem');
final _sha = sha256.convert(_bytes).toString();
final _base = Uri.parse('http://192.168.0.10:8787/');

ContentItem _item({String? sha, String id = 'm1'}) => ContentItem(
      mediaId: id,
      kind: MediaKinds.image,
      name: 'Imagem',
      sha256: sha ?? _sha,
    );

void main() {
  late Directory dir;
  late List<http.BaseRequest> requests;
  late http.Response Function() respond;
  late MediaCache cache;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('media_cache_test');
    requests = [];
    respond = () => http.Response.bytes(_bytes, 200);
    cache = MediaCache(
      root: Directory('${dir.path}/media'),
      client: MockClient((request) async {
        requests.add(request);
        // Deixa os downloads simultâneos se sobreporem.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return respond();
      }),
    );
  });

  tearDown(() => dir.delete(recursive: true));

  List<String> files() => [
        for (final f in Directory('${dir.path}/media').listSync())
          f.uri.pathSegments.last,
      ]..sort();

  test('baixa com o Bearer, confere o hash e guarda pelo sha256', () async {
    final file = await cache.ensure(_item(), base: _base, token: 'segredo');
    expect(await file.readAsBytes(), _bytes);
    expect(file.uri.pathSegments.last, _sha);
    expect(requests.single.headers['Authorization'], 'Bearer segredo');
    expect(requests.single.url.path, '/api/v1/media/m1/file');
    expect(cache.cached(_sha)?.path, file.path);
    expect(files(), [_sha]);
  });

  test('hash errado lança e não deixa arquivo', () async {
    respond = () => http.Response.bytes(utf8.encode('outro'), 200);
    await expectLater(
      cache.ensure(_item(), base: _base, token: 't'),
      throwsA(isA<MediaCacheException>()),
    );
    expect(files(), isEmpty);
    expect(cache.cached(_sha), isNull);
  });

  test('status 404 lança e não deixa arquivo', () async {
    respond = () => http.Response('', 404);
    await expectLater(
      cache.ensure(_item(), base: _base, token: 't'),
      throwsA(isA<MediaCacheException>()),
    );
    expect(files(), isEmpty);
  });

  test('cache hit não baixa de novo', () async {
    await cache.ensure(_item(), base: _base, token: 't');
    await cache.ensure(_item(), base: _base, token: 't');
    expect(requests, hasLength(1));
  });

  test('downloads simultâneos do mesmo hash fazem uma requisição', () async {
    final results = await Future.wait([
      cache.ensure(_item(), base: _base, token: 't'),
      cache.ensure(_item(id: 'm2'), base: _base, token: 't'),
    ]);
    expect(requests, hasLength(1));
    expect(results[0].path, results[1].path);
  });

  test('prune apaga o que não está em keep e os .part', () async {
    await cache.ensure(_item(), base: _base, token: 't');
    final other = 'a' * 64;
    File('${dir.path}/media/$other').writeAsStringSync('x');
    File('${dir.path}/media/${'b' * 64}.part').writeAsStringSync('x');

    await cache.prune({_sha});
    expect(files(), [_sha]);
  });

  test('sha256 inválido nunca vira caminho', () async {
    expect(cache.cached('../x'), isNull);
    expect(cache.cached('A' * 64), isNull);
    await expectLater(
      cache.ensure(_item(sha: '../x'), base: _base, token: 't'),
      throwsA(isA<MediaCacheException>()),
    );
    expect(requests, isEmpty);
    expect(Directory('${dir.path}/media').existsSync(), isFalse);
  });
}
