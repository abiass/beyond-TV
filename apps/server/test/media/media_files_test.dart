import 'dart:io';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_server/server.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/media_support.dart';

void main() {
  late Directory root;
  late MediaFiles files;

  setUp(() {
    root = Directory.systemTemp.createTempSync('beyond_files_');
    files = MediaFiles(root.path, maxBytes: (kind) => 100);
  });
  tearDown(() => root.deleteSync(recursive: true));

  Stream<List<int>> body(List<int> bytes, {int chunk = 5}) async* {
    for (var i = 0; i < bytes.length; i += chunk) {
      yield bytes.sublist(
        i,
        i + chunk > bytes.length ? bytes.length : i + chunk,
      );
    }
  }

  Future<StoredFile> store(List<int> bytes, String mime, {int? length}) =>
      files.store(body(bytes), declaredMime: mime, contentLength: length);

  Matcher apiError(int status, String code) => throwsA(
    isA<ApiException>()
        .having((e) => e.status, 'status', status)
        .having((e) => e.code, 'code', code),
  );

  List<String> leftovers() => [
    for (final f in Directory(p.join(root.path, 'tmp')).listSync()) f.path,
  ];

  test('aceita cada assinatura com o MIME certo', () async {
    final cases = {
      'image/png': pngBytes(),
      'image/jpeg': jpegBytes(),
      'image/gif': gifBytes(),
      'image/webp': webpBytes(),
      'video/mp4': mp4Bytes(),
      'video/webm': webmBytes(),
    };
    for (final MapEntry(key: mime, value: bytes) in cases.entries) {
      final stored = await store(bytes, mime);

      expect(stored.mime, mime);
      expect(stored.kind, mediaKindForMime(mime));
      expect(stored.sizeBytes, bytes.length);
      expect(stored.sha256, sha256.convert(bytes).toString());
      expect(File(p.join(root.path, stored.sha256)).readAsBytesSync(), bytes);
    }
    expect(leftovers(), isEmpty);
  });

  test('normaliza o MIME declarado (parâmetros e maiúsculas)', () async {
    final stored = await store(pngBytes(), 'Image/PNG; charset=binary');

    expect(stored.mime, 'image/png');
  });

  test('MIME declarado diferente do detectado dá 415', () async {
    await expectLater(
      store(pngBytes(), 'image/jpeg'),
      apiError(415, 'unsupported_media_type'),
    );
    await expectLater(
      store(mp4Bytes(), 'image/png'),
      apiError(415, 'unsupported_media_type'),
    );
    expect(leftovers(), isEmpty);
  });

  test('conteúdo sem assinatura conhecida dá 415', () async {
    await expectLater(
      store(List.filled(20, 7), 'image/png'),
      apiError(415, 'unsupported_media_type'),
    );
    await expectLater(
      store([0x89, 0x50], 'image/png'),
      apiError(415, 'unsupported_media_type'),
    );
  });

  test('tipo fora da lista dá 415', () async {
    for (final mime in ['text/html', 'image/svg+xml', '', 'application/pdf']) {
      await expectLater(
        store(pngBytes(), mime),
        apiError(415, 'unsupported_media_type'),
      );
    }
  });

  test('corpo vazio dá 400', () async {
    await expectLater(store([], 'image/png'), apiError(400, 'bad_request'));
    expect(leftovers(), isEmpty);
  });

  test('Content-Length acima do limite dá 413 sem ler o corpo', () async {
    var read = false;
    final stream = (() async* {
      read = true;
      yield pngBytes();
    })();

    await expectLater(
      files.store(stream, declaredMime: 'image/png', contentLength: 101),
      apiError(413, 'payload_too_large'),
    );
    expect(read, isFalse);
  });

  test('corpo acima do limite sem Content-Length dá 413', () async {
    final big = signed(const [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ], 200);

    await expectLater(
      store(big, 'image/png'),
      apiError(413, 'payload_too_large'),
    );
    expect(leftovers(), isEmpty);
    expect(root.listSync().whereType<File>(), isEmpty);
  });

  test('o limite do corpo é exato', () async {
    final exact = signed(const [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ], 92);

    expect((await store(exact, 'image/png')).sizeBytes, 100);
  });

  test('erro no meio do envio não deixa .part', () async {
    final stream = (() async* {
      yield pngBytes();
      throw const FileSystemException('queda');
    })();

    await expectLater(
      files.store(stream, declaredMime: 'image/png'),
      throwsA(isA<FileSystemException>()),
    );
    expect(leftovers(), isEmpty);
  });

  test('mesmo conteúdo duas vezes vira um arquivo só', () async {
    final a = await store(pngBytes(), 'image/png');
    final b = await store(pngBytes(), 'image/png');

    expect(a.sha256, b.sha256);
    expect(root.listSync().whereType<File>(), hasLength(1));
    expect(leftovers(), isEmpty);
  });

  test('fileFor recusa hash inválido', () async {
    final stored = await store(pngBytes(), 'image/png');

    expect(files.fileFor('../x'), isNull);
    expect(files.fileFor('../../etc/passwd'), isNull);
    expect(files.fileFor(stored.sha256.toUpperCase()), isNull);
    expect(files.fileFor(stored.sha256)?.existsSync(), isTrue);
  });

  test('deleteIfUnused só apaga se ninguém usa', () async {
    final stored = await store(pngBytes(), 'image/png');
    final file = files.fileFor(stored.sha256)!;

    await files.deleteIfUnused(stored.sha256, (_) => true);
    expect(file.existsSync(), isTrue);

    await files.deleteIfUnused(stored.sha256, (_) => false);
    expect(file.existsSync(), isFalse);

    await files.deleteIfUnused('../x', (_) => false); // não explode
  });

  test('a criação apaga sobras de tmp/', () {
    final tmp = Directory(p.join(root.path, 'tmp'))..createSync();
    File(p.join(tmp.path, 'velho.part')).writeAsStringSync('x');

    MediaFiles(root.path);

    expect(tmp.existsSync() ? tmp.listSync() : [], isEmpty);
  });
}
