import 'package:beyond_protocol/beyond_protocol.dart';

/// Agendamento de uma playlist numa TV ou num grupo, no relógio local da TV.
class Schedule {
  const Schedule({
    required this.id,
    required this.name,
    required this.playlistId,
    required this.days,
    required this.startMinute,
    required this.endMinute,
    required this.priority,
    required this.createdAt,
    this.deviceId,
    this.groupId,
  });

  factory Schedule.fromJson(Map<String, Object?> json) => Schedule(
        id: json['id']! as String,
        name: json['name']! as String,
        playlistId: json['playlistId']! as String,
        deviceId: json['deviceId'] as String?,
        groupId: json['groupId'] as int?,
        days: {
          for (final d in (json['days'] as List?) ?? const [])
            if (d is int) d,
        },
        startMinute: parseClockTime(json['start']! as String) ?? 0,
        endMinute: parseClockTime(json['end']! as String) ?? 0,
        priority: json['priority']! as int,
        createdAt: DateTime.parse(json['createdAt']! as String),
      );

  final String id;
  final String name;
  final String playlistId;

  /// Exatamente um entre [deviceId] e [groupId] é preenchido.
  final String? deviceId;
  final int? groupId;

  /// Dias ISO em que a faixa começa: 1 = segunda ... 7 = domingo.
  final Set<int> days;
  final int startMinute;
  final int endMinute;
  final int priority;
  final DateTime createdAt;

  bool get isDevice => deviceId != null;

  /// Termina no dia seguinte (`end < start`).
  bool get overnight => endMinute < startMinute;

  /// Cobre 24 horas (`end == start`).
  bool get allDay => endMinute == startMinute;

  /// Corpo de `POST /schedules` (sem `id` e `createdAt`).
  Map<String, Object?> toJson() => {
        'name': name,
        'playlistId': playlistId,
        if (deviceId != null) 'deviceId': deviceId,
        if (groupId != null) 'groupId': groupId,
        'days': (days.toList()..sort()),
        'start': formatClockTime(startMinute),
        'end': formatClockTime(endMinute),
        'priority': priority,
      };
}

/// Ordem de precedência do contrato: prioridade maior primeiro; no empate,
/// TV antes de grupo; depois o criado por último.
int compareByPrecedence(Schedule a, Schedule b) {
  final byPriority = b.priority.compareTo(a.priority);
  if (byPriority != 0) return byPriority;
  if (a.isDevice != b.isDevice) return a.isDevice ? -1 : 1;
  return b.createdAt.compareTo(a.createdAt);
}
