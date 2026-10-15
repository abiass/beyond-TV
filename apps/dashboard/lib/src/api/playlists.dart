import 'media.dart';

/// Playlist na listagem: sem os itens.
class PlaylistSummary {
  const PlaylistSummary({
    required this.id,
    required this.name,
    required this.itemCount,
    required this.createdAt,
  });

  factory PlaylistSummary.fromJson(Map<String, Object?> json) =>
      PlaylistSummary(
        id: json['id']! as String,
        name: json['name']! as String,
        itemCount: json['itemCount']! as int,
        createdAt: DateTime.parse(json['createdAt']! as String),
      );

  final String id;
  final String name;
  final int itemCount;
  final DateTime createdAt;
}

/// Um item da playlist: a mídia e quanto tempo ela fica na tela.
class PlaylistEntry {
  const PlaylistEntry({required this.media, this.durationSeconds});

  factory PlaylistEntry.fromJson(Map<String, Object?> json) => PlaylistEntry(
        media: Media.fromJson(json['media']! as Map<String, Object?>),
        durationSeconds: json['durationSeconds'] as int?,
      );

  final Media media;

  /// `null` = duração padrão (ou até o fim, para vídeo).
  final int? durationSeconds;
}

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    this.items = const [],
  });

  factory Playlist.fromJson(Map<String, Object?> json) => Playlist(
        id: json['id']! as String,
        name: json['name']! as String,
        createdAt: DateTime.parse(json['createdAt']! as String),
        items: [
          for (final item in (json['items'] as List?) ?? const [])
            if (item is Map<String, Object?>) PlaylistEntry.fromJson(item),
        ],
      );

  final String id;
  final String name;
  final DateTime createdAt;
  final List<PlaylistEntry> items;

  PlaylistSummary get summary => PlaylistSummary(
        id: id,
        name: name,
        itemCount: items.length,
        createdAt: createdAt,
      );
}
