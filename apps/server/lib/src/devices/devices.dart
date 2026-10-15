import 'dart:convert';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:sqlite3/sqlite3.dart';

import '../clock.dart';

/// Acesso às tabelas `devices` e `settings`.
class DeviceStore {
  DeviceStore(this._db, {Clock clock = DateTime.now}) : _clock = clock;

  final Database _db;
  final Clock _clock;

  /// Identificador deste servidor, gerado na primeira execução.
  String get serverId =>
      _db
              .select("SELECT value FROM settings WHERE key = 'server_id'")
              .single['value']
          as String;

  /// Cadastra uma TV recém-pareada.
  ///
  /// [tokenHash] é o SHA-256 do token; o token em claro nunca é gravado.
  void create({
    required String id,
    required String name,
    required String tokenHash,
    required DeviceInfo info,
  }) => _db.execute(
    'INSERT INTO devices (id, name, token_hash, info, created_at) '
    'VALUES (?, ?, ?, ?, ?)',
    [id, name, tokenHash, jsonEncode(info.toJson()), isoUtc(_clock())],
  );

  /// Nome da TV [id], ou `null` se ela não existe (ex.: foi removida).
  String? nameOf(String id) {
    final rows = _db.select('SELECT name FROM devices WHERE id = ?', [id]);
    return rows.isEmpty ? null : rows.single['name'] as String;
  }

  /// TV dona do token de hash [tokenHash], ou `null` se não existe.
  ({String id, String name})? findByTokenHash(String tokenHash) {
    final rows = _db.select(
      'SELECT id, name FROM devices WHERE token_hash = ?',
      [tokenHash],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return (id: row['id'] as String, name: row['name'] as String);
  }

  /// Grava os dados informados pela TV no `hello`.
  void updateInfo(String id, DeviceInfo info) => _db.execute(
    'UPDATE devices SET info = ? WHERE id = ?',
    [jsonEncode(info.toJson()), id],
  );

  /// Registra que a TV [id] deu sinal de vida em [at].
  void touch(String id, DateTime at) => _db.execute(
    'UPDATE devices SET last_seen_at = ? WHERE id = ?',
    [isoUtc(at), id],
  );

  /// Todas as TVs, da mais nova para a mais antiga.
  List<DeviceRow> list() => [
    for (final row in _db.select(
      'SELECT id, name, group_id, info, last_seen_at, created_at, media_id, '
      'playlist_id '
      'FROM devices ORDER BY created_at DESC, id',
    ))
      _toRow(row),
  ];

  /// A TV [id], ou `null` se não existe.
  DeviceRow? find(String id) {
    final rows = _db.select(
      'SELECT id, name, group_id, info, last_seen_at, created_at, media_id, '
      'playlist_id '
      'FROM devices WHERE id = ?',
      [id],
    );
    return rows.isEmpty ? null : _toRow(rows.single);
  }

  /// Renomeia a TV [id]. Devolve `false` se ela não existe.
  bool rename(String id, String name) {
    _db.execute('UPDATE devices SET name = ? WHERE id = ?', [name, id]);
    return _db.updatedRows > 0;
  }

  /// Põe a TV [id] no grupo [groupId] (`null` tira do grupo). Devolve `false`
  /// se a TV não existe; o grupo precisa existir (validado pela API).
  bool setGroup(String id, int? groupId) {
    _db.execute('UPDATE devices SET group_id = ? WHERE id = ?', [groupId, id]);
    return _db.updatedRows > 0;
  }

  /// Define a mídia exibida pela TV [deviceId] (`null` limpa).
  /// Devolve `false` se a TV não existe.
  bool setMedia(String deviceId, String? mediaId) =>
      setContent(deviceId, mediaId: mediaId);

  /// Define o que a TV [deviceId] exibe: uma mídia avulsa ou uma playlist.
  ///
  /// Grava um e zera o outro; sem nenhum dos dois, limpa. Devolve `false` se
  /// a TV não existe.
  bool setContent(String deviceId, {String? mediaId, String? playlistId}) {
    assert(mediaId == null || playlistId == null);
    _db.execute(
      'UPDATE devices SET media_id = ?, playlist_id = ? WHERE id = ?',
      [mediaId, playlistId, deviceId],
    );
    return _db.updatedRows > 0;
  }

  /// Ids das TVs que exibem a playlist [playlistId].
  List<String> devicesShowingPlaylist(String playlistId) => [
    for (final row in _db.select(
      'SELECT id FROM devices WHERE playlist_id = ? ORDER BY id',
      [playlistId],
    ))
      row['id'] as String,
  ];

  /// Ids das TVs que exibem a mídia [mediaId].
  List<String> devicesShowing(String mediaId) => [
    for (final row in _db.select(
      'SELECT id FROM devices WHERE media_id = ? ORDER BY id',
      [mediaId],
    ))
      row['id'] as String,
  ];

  /// Apaga a TV [id] (e, com ela, o hash do token). `false` se não existe.
  bool delete(String id) {
    _db.execute('DELETE FROM devices WHERE id = ?', [id]);
    return _db.updatedRows > 0;
  }

  DeviceRow _toRow(Row row) {
    final info = jsonDecode(row['info'] as String) as Map<String, Object?>;
    final lastSeen = row['last_seen_at'] as String?;
    return DeviceRow(
      id: row['id'] as String,
      name: row['name'] as String,
      groupId: row['group_id'] as int?,
      info: info.isEmpty ? null : DeviceInfo.fromJson(info),
      lastSeenAt: lastSeen == null ? null : DateTime.parse(lastSeen).toUtc(),
      createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
      mediaId: row['media_id'] as String?,
      playlistId: row['playlist_id'] as String?,
    );
  }
}

/// Uma linha da tabela `devices`, sem o hash do token.
class DeviceRow {
  const DeviceRow({
    required this.id,
    required this.name,
    required this.createdAt,
    this.groupId,
    this.info,
    this.lastSeenAt,
    this.mediaId,
    this.playlistId,
  });

  final String id;
  final String name;
  final int? groupId;

  /// Dados do último `hello` ou do pareamento; `null` se o JSON é `{}`.
  final DeviceInfo? info;
  final DateTime? lastSeenAt;
  final DateTime createdAt;

  /// Mídia que a TV deve exibir, se definida.
  final String? mediaId;

  /// Playlist que a TV deve exibir, se definida (exclusiva com [mediaId]).
  final String? playlistId;
}
