import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:sqlite3/sqlite3.dart';

import '../auth/tokens.dart';
import '../clock.dart';

/// Converte dias ISO (1 = segunda até 7 = domingo) no bitmask da coluna
/// `schedules.days`: o dia `d` liga o bit `d - 1`.
int daysToMask(Iterable<int> days) =>
    days.fold(0, (mask, day) => mask | (1 << (day - 1)));

/// Dias ISO ligados em [mask], em ordem crescente.
List<int> maskToDays(int mask) => [
  for (var day = 1; day <= 7; day++)
    if (mask & (1 << (day - 1)) != 0) day,
];

/// Acesso à tabela `schedules`.
class ScheduleStore {
  ScheduleStore(this._db, {Clock clock = DateTime.now}) : _clock = clock;

  final Database _db;
  final Clock _clock;

  static const _select =
      'SELECT id, name, playlist_id, device_id, group_id, days, start_min, '
      'end_min, priority, created_at FROM schedules';

  /// Ordem de precedência: prioridade, TV antes de grupo, mais recente.
  static const _precedence =
      'ORDER BY priority DESC, (device_id IS NULL), created_at DESC, id';

  /// Agendamentos, por nome. [deviceId] ou [groupId] filtram pelo alvo
  /// direto (sem misturar o grupo da TV).
  List<ScheduleRow> list({String? deviceId, int? groupId}) => [
    for (final row in _db.select(
      '$_select WHERE (?1 IS NULL OR device_id = ?1) '
      'AND (?2 IS NULL OR group_id = ?2) '
      'ORDER BY name COLLATE NOCASE, id',
      [deviceId, groupId],
    ))
      _toRow(row),
  ];

  /// O agendamento [id], ou `null` se não existe.
  ScheduleRow? find(String id) {
    final rows = _db.select('$_select WHERE id = ?', [id]);
    return rows.isEmpty ? null : _toRow(rows.single);
  }

  /// As regras da TV [deviceId] e do grupo dela ([groupId]), já na ordem de
  /// precedência.
  List<ScheduleRow> forDevice(String deviceId, int? groupId) => [
    for (final row in _db.select(
      '$_select WHERE device_id = ?1 OR group_id = ?2 $_precedence',
      [deviceId, groupId],
    ))
      _toRow(row),
  ];

  /// Cria o agendamento. A API valida os campos e a existência dos alvos.
  ScheduleRow create(ScheduleData data) {
    final id = generateId();
    _db.execute(
      'INSERT INTO schedules (id, name, playlist_id, device_id, group_id, '
      'days, start_min, end_min, priority, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        data.name,
        data.playlistId,
        data.deviceId,
        data.groupId,
        daysToMask(data.days),
        data.startMinute,
        data.endMinute,
        data.priority,
        isoUtc(_clock()),
      ],
    );
    return find(id)!;
  }

  /// Substitui os campos do agendamento [id]. `false` se não existe.
  bool update(String id, ScheduleData data) {
    _db.execute(
      'UPDATE schedules SET name = ?, playlist_id = ?, device_id = ?, '
      'group_id = ?, days = ?, start_min = ?, end_min = ?, priority = ? '
      'WHERE id = ?',
      [
        data.name,
        data.playlistId,
        data.deviceId,
        data.groupId,
        daysToMask(data.days),
        data.startMinute,
        data.endMinute,
        data.priority,
        id,
      ],
    );
    return _db.updatedRows > 0;
  }

  bool delete(String id) {
    _db.execute('DELETE FROM schedules WHERE id = ?', [id]);
    return _db.updatedRows > 0;
  }

  ScheduleRow _toRow(Row row) => ScheduleRow(
    id: row['id'] as String,
    data: ScheduleData(
      name: row['name'] as String,
      playlistId: row['playlist_id'] as String,
      deviceId: row['device_id'] as String?,
      groupId: row['group_id'] as int?,
      days: maskToDays(row['days'] as int).toSet(),
      startMinute: row['start_min'] as int,
      endMinute: row['end_min'] as int,
      priority: row['priority'] as int,
    ),
    createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
  );
}

/// Os campos editáveis de um agendamento.
class ScheduleData {
  const ScheduleData({
    required this.name,
    required this.playlistId,
    required this.days,
    required this.startMinute,
    required this.endMinute,
    required this.priority,
    this.deviceId,
    this.groupId,
  });

  final String name;
  final String playlistId;

  /// Exatamente um entre [deviceId] e [groupId] é não nulo.
  final String? deviceId;
  final int? groupId;

  /// Dias ISO em que a faixa começa.
  final Set<int> days;
  final int startMinute;
  final int endMinute;
  final int priority;
}

/// Uma linha da tabela `schedules`.
class ScheduleRow {
  const ScheduleRow({
    required this.id,
    required this.data,
    required this.createdAt,
  });

  final String id;
  final ScheduleData data;
  final DateTime createdAt;

  String get target =>
      data.deviceId != null ? ScheduleTargets.device : ScheduleTargets.group;

  /// Formato `Schedule` do protocolo.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': data.name,
    'playlistId': data.playlistId,
    'deviceId': data.deviceId,
    'groupId': data.groupId,
    'days': data.days.toList()..sort(),
    'start': formatClockTime(data.startMinute),
    'end': formatClockTime(data.endMinute),
    'priority': data.priority,
    'createdAt': createdAt.toIso8601String(),
  };
}
