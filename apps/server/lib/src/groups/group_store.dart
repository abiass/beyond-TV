import 'package:sqlite3/sqlite3.dart';

import '../clock.dart';

/// Acesso à tabela `groups` e à coluna `devices.group_id`.
class GroupStore {
  GroupStore(this._db, {Clock clock = DateTime.now}) : _clock = clock;

  final Database _db;
  final Clock _clock;

  static const _select =
      'SELECT id, name, created_at, media_id, playlist_id FROM groups';

  /// Todos os grupos, por nome.
  List<GroupRow> list() => [
    for (final row in _db.select('$_select ORDER BY name COLLATE NOCASE, id'))
      _toRow(row),
  ];

  /// O grupo [id], ou `null` se não existe.
  GroupRow? find(int id) {
    final rows = _db.select('$_select WHERE id = ?', [id]);
    return rows.isEmpty ? null : _toRow(rows.single);
  }

  /// Se já existe outro grupo chamado [name] (sem diferenciar maiúsculas).
  bool nameTaken(String name, {int? exceptId}) => _db.select(
    'SELECT 1 FROM groups WHERE name = ? AND id IS NOT ?',
    [name, exceptId],
  ).isNotEmpty;

  /// Cria o grupo. Nome repetido lança [SqliteException].
  GroupRow create(String name) {
    _db.execute('INSERT INTO groups (name, created_at) VALUES (?, ?)', [
      name,
      isoUtc(_clock()),
    ]);
    return find(_db.lastInsertRowId)!;
  }

  /// Renomeia. Devolve `false` se o grupo não existe.
  bool rename(int id, String name) {
    _db.execute('UPDATE groups SET name = ? WHERE id = ?', [name, id]);
    return _db.updatedRows > 0;
  }

  /// Apaga o grupo: as TVs ficam sem grupo e os agendamentos dele somem.
  bool delete(int id) {
    _db.execute('DELETE FROM groups WHERE id = ?', [id]);
    return _db.updatedRows > 0;
  }

  /// Ids das TVs do grupo [id].
  List<String> memberIds(int id) => [
    for (final row in _db.select(
      'SELECT id FROM devices WHERE group_id = ? ORDER BY id',
      [id],
    ))
      row['id'] as String,
  ];

  /// Define os membros do grupo [id] numa transação.
  ///
  /// As TVs de [deviceIds] entram (saindo do grupo anterior) e as demais
  /// saem. Devolve os ids das TVs cujo grupo mudou. Id de TV desconhecido
  /// lança [ArgumentError] sem alterar nada.
  Set<String> setMembers(int id, List<String> deviceIds) {
    final wanted = deviceIds.toSet();
    final known = {
      for (final row in _db.select('SELECT id FROM devices'))
        row['id'] as String,
    };
    final unknown = wanted.difference(known);
    if (unknown.isNotEmpty) {
      throw ArgumentError('TV desconhecida: ${unknown.first}');
    }
    final current = memberIds(id).toSet();
    final moved = <String>{...current.difference(wanted)};
    _db.execute('BEGIN');
    try {
      for (final deviceId in wanted) {
        final row = _db.select('SELECT group_id FROM devices WHERE id = ?', [
          deviceId,
        ]);
        if (row.single['group_id'] != id) moved.add(deviceId);
      }
      _db.execute('UPDATE devices SET group_id = NULL WHERE group_id = ?', [
        id,
      ]);
      final update = _db.prepare(
        'UPDATE devices SET group_id = ? WHERE id = ?',
      );
      try {
        for (final deviceId in wanted) {
          update.execute([id, deviceId]);
        }
      } finally {
        update.close();
      }
      _db.execute('COMMIT');
    } on Object {
      _db.execute('ROLLBACK');
      rethrow;
    }
    return moved;
  }

  /// Define o conteúdo padrão do grupo: uma mídia ou uma playlist; sem
  /// nenhuma das duas, limpa. Devolve `false` se o grupo não existe.
  bool setContent(int id, {String? mediaId, String? playlistId}) {
    assert(mediaId == null || playlistId == null);
    _db.execute(
      'UPDATE groups SET media_id = ?, playlist_id = ? WHERE id = ?',
      [mediaId, playlistId, id],
    );
    return _db.updatedRows > 0;
  }

  GroupRow _toRow(Row row) {
    final id = row['id'] as int;
    return GroupRow(
      id: id,
      name: row['name'] as String,
      createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
      deviceIds: memberIds(id),
      mediaId: row['media_id'] as String?,
      playlistId: row['playlist_id'] as String?,
    );
  }
}

/// Uma linha da tabela `groups`, com os ids das TVs.
class GroupRow {
  const GroupRow({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.deviceIds,
    this.mediaId,
    this.playlistId,
  });

  final int id;
  final String name;
  final DateTime createdAt;
  final List<String> deviceIds;

  /// Mídia padrão do grupo, se definida.
  final String? mediaId;

  /// Playlist padrão do grupo, se definida (exclusiva com [mediaId]).
  final String? playlistId;
}
