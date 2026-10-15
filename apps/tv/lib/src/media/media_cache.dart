import 'dart:async';
import 'dart:io';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Falha ao baixar ou conferir um arquivo de mídia.
final class MediaCacheException implements Exception {
  const MediaCacheException(this.message);

  final String message;

  @override
  String toString() => 'MediaCacheException: $message';
}

/// Cache de arquivos de mídia em disco, nomeados pelo sha256.
///
/// O arquivo só aparece com o nome final depois de baixado por inteiro e
/// com o hash conferido; antes disso vive como `<sha256>.part`.
class MediaCache {
  MediaCache({required this.root, required http.Client client})
      : _client = client;

  /// Pasta dos arquivos (`<app support>/media`).
  final Directory root;
  final http.Client _client;

  final Map<String, Future<File>> _downloads = {};

  /// Arquivo em cache, ou `null` se ainda não foi baixado.
  ///
  /// [sha256] que não seja hexadecimal minúsculo de 64 caracteres nunca vira
  /// caminho.
  File? cached(String sha256) {
    if (!isSha256Hex(sha256)) return null;
    final file = File('${root.path}/$sha256');
    return file.existsSync() ? file : null;
  }

  /// Garante que o arquivo de [item] esteja em cache e o devolve.
  ///
  /// Baixa de [base] com o [token] da TV. Chamadas simultâneas para o mesmo
  /// hash compartilham o mesmo download.
  Future<File> ensure(
    ContentItem item, {
    required Uri base,
    required String token,
  }) {
    final sha = item.sha256;
    if (sha == null || !isSha256Hex(sha)) {
      return Future.error(const MediaCacheException('sha256 inválido'));
    }
    final hit = cached(sha);
    if (hit != null) return Future.value(hit);
    return _downloads[sha] ??=
        _download(item, sha, base, token).whenComplete(() {
      // Bloco, não seta: devolver o Future removido travaria o whenComplete.
      _downloads.remove(sha);
    });
  }

  Future<File> _download(
    ContentItem item,
    String sha,
    Uri base,
    String token,
  ) async {
    await root.create(recursive: true);
    final part = File('${root.path}/$sha.part');
    final sink = part.openWrite();
    var sinkClosed = false;
    try {
      final request =
          http.Request('GET', base.resolve(mediaFilePath(item.mediaId)))
            ..headers['Authorization'] = 'Bearer $token';
      final response = await _client.send(request);
      if (response.statusCode != 200) {
        throw MediaCacheException('download falhou: ${response.statusCode}');
      }
      final digest = _DigestSink();
      final hasher = sha256.startChunkedConversion(digest);
      await for (final chunk in response.stream) {
        hasher.add(chunk);
        sink.add(chunk);
      }
      hasher.close();
      await sink.close();
      sinkClosed = true;
      if (digest.value.toString() != sha) {
        throw const MediaCacheException('sha256 do arquivo não confere');
      }
      return await part.rename('${root.path}/$sha');
    } on Object {
      if (!sinkClosed) {
        try {
          await sink.close();
        } on Object {
          // Já falhou; o que importa é apagar o .part.
        }
      }
      if (part.existsSync()) await part.delete();
      rethrow;
    }
  }

  /// Apaga os arquivos que não estão em [keep], e os `.part` órfãos.
  Future<void> prune(Set<String> keep) async {
    if (!root.existsSync()) return;
    await for (final entity in root.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final inUse = keep.contains(name) ||
          (name.endsWith('.part') &&
              _downloads.containsKey(name.substring(0, name.length - 5)));
      if (inUse) continue;
      try {
        await entity.delete();
      } on FileSystemException {
        // Sumiu no meio do caminho; nada a fazer.
      }
    }
  }

  void close() => _client.close();
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
