import '../api/schedules.dart';

/// Um trecho de um agendamento dentro de um único dia da grade semanal.
class ScheduleBlock {
  const ScheduleBlock({
    required this.schedule,
    required this.day,
    required this.startMinute,
    required this.endMinute,
  });

  final Schedule schedule;

  /// Dia ISO (1 = segunda ... 7 = domingo).
  final int day;

  /// Início e fim dentro do dia, em minutos (0 a 1440).
  final int startMinute;
  final int endMinute;

  @override
  bool operator ==(Object other) =>
      other is ScheduleBlock &&
      other.schedule.id == schedule.id &&
      other.day == day &&
      other.startMinute == startMinute &&
      other.endMinute == endMinute;

  @override
  int get hashCode => Object.hash(schedule.id, day, startMinute, endMinute);

  @override
  String toString() => 'ScheduleBlock(day $day, $startMinute-$endMinute)';
}

const _minutesPerDay = 24 * 60;

/// Trechos de [schedule] na grade semanal, ordenados por dia e início.
///
/// Faixa que vira a noite vira dois trechos: do início até a meia-noite no
/// dia em que começa e da meia-noite até o fim no dia seguinte (domingo
/// volta para segunda). `end == start` cobre 24 horas a partir do início.
List<ScheduleBlock> blocksFor(Schedule schedule) {
  final start = schedule.startMinute;
  final end = schedule.endMinute;
  final blocks = <ScheduleBlock>[];

  void add(int day, int from, int to) {
    if (to > from) {
      blocks.add(
        ScheduleBlock(
          schedule: schedule,
          day: day,
          startMinute: from,
          endMinute: to,
        ),
      );
    }
  }

  for (final day in schedule.days) {
    final next = day % 7 + 1;
    if (end > start) {
      add(day, start, end);
    } else {
      // Vira a noite (`end < start`) ou 24 h (`end == start`).
      add(day, start, _minutesPerDay);
      add(next, 0, end);
    }
  }
  blocks.sort((a, b) {
    final byDay = a.day.compareTo(b.day);
    return byDay != 0 ? byDay : a.startMinute.compareTo(b.startMinute);
  });
  return blocks;
}
