import 'dart:io';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../auth/tokens.dart';
import '../http/json.dart';

/// Arquivo gravado por [MediaFiles.store].
class StoredFile {
  const StoredFile({
    required this.sha256,
    required this.sizeBytes,
    required this.mime,
    required this.kind,
  });

  final String sha256;
  final int sizeBytes;

  /// MIME normalizado (sem parâmetros).
  final String mime;

  /// Um dos `MediaKinds`: `image` ou `video`.
  final String kind;
}

/// Guarda os arquivos de mídia em `dir/<sha256>`.
///
/// Os envios passam antes por `dir/tmp/`; sobras de envios interrompidos são
/// apagadas na criação.
class MediaFiles {
  /// [maxBytes] existe para os testes usarem limites pequenos.
  MediaFiles(this.dir, {int Function(String kind) maxBytes = maxBytesForKind})
    : _maxBytes = maxBytes {
    final tmp = Directory(_tmpDir);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  }

  final String dir;
  final int Function(String kind) _maxBytes;

  String get _tmpDir => p.join(dir, 'tmp');

  /// Grava [body] e devolve os dados do arquivo.
  ///
  /// Lança [ApiException]: `415` se o tipo não é aceito ou os primeiros bytes
  /// não batem com [declaredMime], `413` se passa do limite (mesmo sem
  /// [contentLength]) e `400` se o corpo é vazio.
  Future<StoredFile> store(
    Stream<List<int>> body, {
    required String declaredMime,
    int? contentLength,
  }) async {
    final mime = declaredMime.split(';').first.trim().toLowerCase();
    final kind = mediaKindForMime(mime);
    if (kind == null) {
      throw const ApiException.unsupportedMediaType(
        'Tipo de arquivo não aceito. Use PNG, JPEG, WebP, GIF, MP4 ou WebM.',
      );
    }
    final limit = _maxBytes(kind);
    if (contentLength != null && contentLength > limit) {
      throw const ApiException.payloadTooLarge('O arquivo é grande demais.');
    }

    await Directory(_tmpDir).create(recursive: true);
    final part = File(p.join(_tmpDir, '${generateId()}.part'));
    final out = part.openWrite();
    final digests = _DigestCollector();
    final hasher = sha256.startChunkedConversion(digests);
    final head = <int>[];
    var size = 0;
    var committed = false;
    try {
      await for (final chunk in body) {
        size += chunk.length;
        if (size > limit) {
          throw const ApiException.payloadTooLarge(
            'O arquivo é grande demais.',
          );
        }
        if (head.length < _headLength) {
          head.addAll(chunk.take(_headLength - head.length));
        }
        hasher.add(chunk);
        out.add(chunk);
      }
      hasher.close();
      await out.close();

      if (size == 0) {
        throw const ApiException.badRequest('O arquivo está vazio.');
      }
      if (detectMime(head) != mime) {
        throw const ApiException.unsupportedMediaType(
          'O conteúdo do arquivo não corresponde ao tipo informado.',
        );
      }

      final hash = digests.digest.toString();
      final target = File(p.join(dir, hash));
      if (target.existsSync()) {
        await part.delete();
      } else {
        await part.rename(target.path);
      }
      committed = true;
      return StoredFile(sha256: hash, sizeBytes: size, mime: mime, kind: kind);
    } finally {
      if (!committed) {
        try {
          await out.close();
        } on Object {
          // Já fechado ou com erro de escrita; só interessa apagar o .part.
        }
        if (part.existsSync()) await part.delete();
      }
    }
  }

  /// O arquivo com hash [sha256], ou `null` se o hash é inválido.
  ///
  /// Só aceita 64 hexadecimais minúsculos, o que impede path traversal. O
  /// arquivo pode não existir no disco.
  File? fileFor(String sha256) =>
      isSha256Hex(sha256) ? File(p.join(dir, sha256)) : null;

  /// Apaga o arquivo [sha256] se [inUse] disser que nenhuma mídia o usa.
  Future<void> deleteIfUnused(
    String sha256,
    bool Function(String sha256) inUse,
  ) async {
    final file = fileFor(sha256);
    if (file == null || inUse(sha256)) return;
    if (file.existsSync()) await file.delete();
  }

  static const _headLength = 16;

  /// MIME indicado pelos primeiros bytes de [head], ou `null`.
  static String? detectMime(List<int> head) {
    bool starts(List<int> sig, [int offset = 0]) =>
        head.length >= offset + sig.length &&
        [
          for (var i = 0; i < sig.length; i++) head[offset + i] == sig[i],
        ].every((ok) => ok);

    if (starts(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return 'image/png';
    }
    if (starts(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (starts('GIF87a'.codeUnits) || starts('GIF89a'.codeUnits)) {
      return 'image/gif';
    }
    if (starts('RIFF'.codeUnits) && starts('WEBP'.codeUnits, 8)) {
      return 'image/webp';
    }
    if (starts('ftyp'.codeUnits, 4)) return 'video/mp4';
    if (starts(const [0x1A, 0x45, 0xDF, 0xA3])) return 'video/webm';
    return null;
  }
}

/// Recebe o resultado de uma conversão em pedaços.
class _DigestCollector implements Sink<Digest> {
  late Digest digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}
