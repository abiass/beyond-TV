import 'package:beyond_protocol/beyond_protocol.dart';

/// Uma mídia da biblioteca: site, imagem ou vídeo.
class Media {
  const Media({
    required this.id,
    required this.kind,
    required this.name,
    required this.createdAt,
    this.url,
    this.sha256,
    this.sizeBytes,
    this.mime,
  });

  factory Media.fromJson(Map<String, Object?> json) => Media(
        id: json['id']! as String,
        kind: json['kind']! as String,
        name: json['name']! as String,
        url: json['url'] as String?,
        sha256: json['sha256'] as String?,
        sizeBytes: json['sizeBytes'] as int?,
        mime: json['mime'] as String?,
        createdAt: DateTime.parse(json['createdAt']! as String),
      );

  final String id;

  /// Um dos `MediaKinds`.
  final String kind;
  final String name;

  /// Endereço do site, só para `kind == url`.
  final String? url;

  /// Só para imagem e vídeo.
  final String? sha256;
  final int? sizeBytes;
  final String? mime;
  final DateTime createdAt;

  /// Imagem ou vídeo (tem arquivo no servidor).
  bool get isFile => kind == MediaKinds.image || kind == MediaKinds.video;
  bool get isImage => kind == MediaKinds.image;
  bool get isVideo => kind == MediaKinds.video;
  bool get isSite => kind == MediaKinds.url;
}
