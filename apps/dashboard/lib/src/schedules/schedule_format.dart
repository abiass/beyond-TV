import 'package:beyond_protocol/beyond_protocol.dart';

import '../api/schedules.dart';

/// Nomes curtos dos dias ISO, de segunda (1) a domingo (7).
const dayLabels = {
  1: 'Seg',
  2: 'Ter',
  3: 'Qua',
  4: 'Qui',
  5: 'Sex',
  6: 'Sáb',
  7: 'Dom',
};

/// Dias de [days] em texto curto: "Todos os dias", "Seg a Sex" ou a lista.
String describeDays(Set<int> days) {
  final sorted = days.toList()..sort();
  if (sorted.length == 7) return 'Todos os dias';
  final consecutive =
      sorted.length > 2 && sorted.last - sorted.first == sorted.length - 1;
  if (consecutive) {
    return '${dayLabels[sorted.first]} a ${dayLabels[sorted.last]}';
  }
  return sorted.map((d) => dayLabels[d]).join(', ');
}

/// Faixa de horário de [schedule], ex.: "11:00-14:00" ou "22:00-06:00 (+1)".
String describeTimes(Schedule schedule) {
  final range = '${formatClockTime(schedule.startMinute)}-'
      '${formatClockTime(schedule.endMinute)}';
  if (schedule.allDay) return '$range (24 h)';
  return schedule.overnight ? '$range (+1)' : range;
}

/// Resumo de uma linha: dias, horário e prioridade.
String describeSchedule(Schedule schedule) =>
    '${describeDays(schedule.days)} · ${describeTimes(schedule)} · '
    'prioridade ${schedule.priority}';
