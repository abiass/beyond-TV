import 'package:sqlite3/sqlite3.dart';

import '../auth/tokens.dart';
import '../clock.dart';
import '../media/media_store.dart';

/// Acesso às tabelas `playlists` e `playlist_items`.
class PlaylistStore {
  PlaylistStore(this._db, this._media, {Clock clock = DateTime.now})
    : _clock = clock;

  final Database _db;
  final MediaStore _media;
  final Clock _clock;

  static const _select =
      'SELECT p.id, p.name, p.created_at, '
      '(SELECT count(*) FROM playlist_items i WHERE i.playlist_id = p.id) '
      'AS item_count FROM playlists p';

  /// Todas as playlists, por nome.
  List<PlaylistRow> list() => [
    for (final row in _db.select(
      '$_select ORDER BY p.name COLLATE NOCASE, p.id',
    ))
      _toRow(row),
  ];

  /// A playlist [id], ou `null` se não existe.
  PlaylistRow? find(String id) {
    final rows = _db.select('$_select WHERE p.id = ?', [id]);
    return rows.isEmpty ? null : _toRow(rows.single);
  }

  PlaylistRow create(String name) {
    final id = generateId();
    _db.execute(
      'INSERT INTO playlists (id, name, created_at) VALUES (?, ?, ?)',
      [id, name, isoUtc(_clock())],
    );
    return find(id)!;
  }

  /// Renomeia. Devolve `false` se a playlist não existe.
  bool rename(String id, String name) {
    _db.execute('UPDATE playlists SET name = ? WHERE id = ?', [name, id]);
    return _db.updatedRows > 0;
  }

  /// Substitui todos os itens, na ordem dada, numa transação.
  ///
  /// Os `mediaId` precisam existir (a validação é da API).
  void replaceItems(String id, List<(String mediaId, int? duration)> items) {
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM playlist_items WHERE playlist_id = ?', [id]);
      final insert = _db.prepare(
        'INSERT INTO playlist_items (playlist_id, position, media_id, '
        'duration_s) VALUES (?, ?, ?, ?)',
      );
      try {
        for (var i = 0; i < items.length; i++) {
          insert.execute([id, i, items[i].$1, items[i].$2]);
        }
      } finally {
        insert.close();
      }
      _db.execute('COMMIT');
    } on Object {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Apaga a playlist; as TVs que a exibiam ficam sem conteúdo.
  bool delete(String id) {
    _db.execute('DELETE FROM playlists WHERE id = ?', [id]);
    return _db.updatedRows > 0;
  }

  /// Itens da playlist [id], em ordem, já com a mídia.
  List<PlaylistItem> itemsOf(String id) {
    final items = <PlaylistItem>[];
    for (final row in _db.select(
      'SELECT media_id, duration_s FROM playlist_items '
      'WHERE playlist_id = ? ORDER BY position',
      [id],
    )) {
      final media = _media.find(row['media_id'] as String);
      if (media != null) {
        items.add(PlaylistItem(media, row['duration_s'] as int?));
      }
    }
    return items;
  }

  /// Ids das playlists que contêm a mídia [mediaId].
  List<String> playlistsContaining(String mediaId) => [
    for (final row in _db.select(
      'SELECT DISTINCT playlist_id FROM playlist_items WHERE media_id = ? '
      'ORDER BY playlist_id',
      [mediaId],
    ))
      row['playlist_id'] as String,
  ];

  PlaylistRow _toRow(Row row) => PlaylistRow(
    id: row['id'] as String,
    name: row['name'] as String,
    itemCount: row['item_count'] as int,
    createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
  );
}

/// Uma linha da tabela `playlists`.
class PlaylistRow {
  const PlaylistRow({
    required this.id,
    required this.name,
    required this.itemCount,
    required this.createdAt,
  });

  final String id;
  final String name;
  final int itemCount;
  final DateTime createdAt;

  /// Formato `PlaylistSummary` do protocolo.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'itemCount': itemCount,
    'createdAt': createdAt.toIso8601String(),
  };

  /// Formato `Playlist` do protocolo.
  Map<String, Object?> toJsonWith(List<PlaylistItem> items) => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'items': [for (final item in items) item.toJson()],
  };
}

/// Um item de playlist: a mídia e a duração em segundos (`null` = padrão).
class PlaylistItem {
  const PlaylistItem(this.media, this.durationSeconds);

  final MediaRow media;
  final int? durationSeconds;

  Map<String, Object?> toJson() => {
    'media': media.toJson(),
    'durationSeconds': durationSeconds,
  };
}
