import 'package:beyond_protocol/beyond_protocol.dart';

/// Grupo de TVs, com conteúdo padrão próprio.
class Group {
  const Group({
    required this.id,
    required this.name,
    required this.createdAt,
    this.deviceIds = const [],
    this.content,
    this.playlist,
  });

  factory Group.fromJson(Map<String, Object?> json) {
    final content = json['content'];
    final playlist = json['playlist'];
    return Group(
      id: json['id']! as int,
      name: json['name']! as String,
      deviceIds: [
        for (final id in (json['deviceIds'] as List?) ?? const [])
          if (id is String) id,
      ],
      content: content is Map<String, Object?>
          ? ContentItem.fromJson(content)
          : null,
      playlist: playlist is Map<String, Object?>
          ? PlaylistRef.fromJson(playlist)
          : null,
      createdAt: DateTime.parse(json['createdAt']! as String),
    );
  }

  final int id;
  final String name;
  final List<String> deviceIds;

  /// Mídia avulsa padrão do grupo; nunca vem junto com [playlist].
  final ContentItem? content;
  final PlaylistRef? playlist;
  final DateTime createdAt;

  /// Texto curto do conteúdo padrão, ou `null` se não há.
  String? get contentLabel =>
      playlist != null ? 'Playlist: ${playlist!.name}' : content?.name;
}
