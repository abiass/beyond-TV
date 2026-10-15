import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('mediaKindForMime', () {
    test('reconhece imagem e vídeo, ignorando parâmetros e caixa', () {
      expect(mediaKindForMime('image/png'), MediaKinds.image);
      expect(mediaKindForMime('IMAGE/JPEG'), MediaKinds.image);
      expect(mediaKindForMime('video/mp4; codecs="avc1"'), MediaKinds.video);
      expect(mediaKindForMime('video/webm'), MediaKinds.video);
    });

    test('recusa tipos fora da lista', () {
      for (final mime in [
        'image/svg+xml',
        'text/html',
        'application/octet-stream',
        'video/x-msvideo',
        '',
      ]) {
        expect(mediaKindForMime(mime), isNull, reason: mime);
      }
    });
  });

  test('maxBytesForKind separa vídeo de imagem', () {
    expect(maxBytesForKind(MediaKinds.video), maxVideoBytes);
    expect(maxBytesForKind(MediaKinds.image), maxImageBytes);
  });

  test('isSha256Hex aceita só 64 hex minúsculos', () {
    expect(isSha256Hex('a' * 64), isTrue);
    expect(isSha256Hex('A' * 64), isFalse);
    expect(isSha256Hex('a' * 63), isFalse);
    expect(isSha256Hex('../${'a' * 61}'), isFalse);
  });

  test('mediaFilePath escapa o id', () {
    expect(mediaFilePath('abc'), '/api/v1/media/abc/file');
    expect(mediaFilePath('a/b'), '/api/v1/media/a%2Fb/file');
  });

  test('isValidItemDuration respeita os limites', () {
    expect(isValidItemDuration(null), isTrue);
    expect(isValidItemDuration(minItemDurationSeconds), isTrue);
    expect(isValidItemDuration(maxItemDurationSeconds), isTrue);
    expect(isValidItemDuration(minItemDurationSeconds - 1), isFalse);
    expect(isValidItemDuration(maxItemDurationSeconds + 1), isFalse);
  });

  test('DeviceSummary leva a playlist por JSON', () {
    final device = DeviceSummary(
      id: 'd1',
      name: 'Recepção',
      online: true,
      createdAt: DateTime.utc(2026, 10, 15),
      playlist: const PlaylistRef(id: 'p1', name: 'Manhã'),
    );

    final decoded = DeviceSummary.fromJson(device.toJson());

    expect(decoded.playlist, const PlaylistRef(id: 'p1', name: 'Manhã'));
    expect(decoded.content, isNull);
    expect(decoded.copyWith(online: false).playlist, decoded.playlist);
  });
}
