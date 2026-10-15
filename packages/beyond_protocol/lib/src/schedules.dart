import 'content.dart';
import 'json_fields.dart';
import 'protocol_exception.dart';

/// A quem um agendamento se aplica.
abstract final class ScheduleTargets {
  static const device = 'device';
  static const group = 'group';

  static const all = {device, group};
}

/// Minutos num dia.
const minutesPerDay = 24 * 60;

/// Maior prioridade aceita num agendamento (a menor é 0).
const maxSchedulePriority = 100;

/// Converte `"HH:MM"` (de `00:00` a `23:59`) em minutos desde a meia-noite.
///
/// Devolve `null` se o formato é inválido.
int? parseClockTime(String value) {
  final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(value);
  if (match == null) return null;
  return int.parse(match[1]!) * 60 + int.parse(match[2]!);
}

/// Formata [minutes] (0 a 1439) como `"HH:MM"`.
String formatClockTime(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// Uma regra de agenda: exibe [items] nos dias [days], de [startMinute] até
/// [endMinute], no relógio local da TV.
///
/// Se [endMinute] não é maior que [startMinute], a faixa vira a noite: começa
/// num dia de [days] e termina no dia seguinte.
final class ScheduleRule {
  ScheduleRule({
    required this.id,
    required Set<int> days,
    required this.startMinute,
    required this.endMinute,
    required this.priority,
    required this.target,
    required this.items,
  }) : days = Set.unmodifiable(days);

  factory ScheduleRule.fromJson(Map<String, Object?> json) {
    final start = parseClockTime(json.field<String>('start'));
    final end = parseClockTime(json.field<String>('end'));
    if (start == null || end == null) {
      throw const ProtocolException('Horário inválido no agendamento.');
    }
    return ScheduleRule(
      id: json.field<String>('id'),
      days: {
        for (final day in json.field<List<Object?>>('days'))
          if (day is int && day >= DateTime.monday && day <= DateTime.sunday)
            day,
      },
      startMinute: start,
      endMinute: end,
      priority: json.field<int>('priority'),
      target: json.field<String>('target'),
      items: [
        for (final item in json.field<List<Object?>>('items'))
          if (item is Map<String, Object?>) ContentItem.fromJson(item),
      ],
    );
  }

  final String id;

  /// Dias da semana em que a faixa começa (`DateTime.monday` = 1 até
  /// `DateTime.sunday` = 7).
  final Set<int> days;
  final int startMinute;
  final int endMinute;
  final int priority;

  /// Um dos [ScheduleTargets]; informativo para a TV.
  final String target;
  final List<ContentItem> items;

  bool get isOvernight => endMinute <= startMinute;

  /// Se a regra vale no horário local [now].
  bool isActiveAt(DateTime now) {
    final minute = now.hour * 60 + now.minute;
    if (!isOvernight) {
      return days.contains(now.weekday) &&
          minute >= startMinute &&
          minute < endMinute;
    }
    final yesterday =
        now.weekday == DateTime.monday ? DateTime.sunday : now.weekday - 1;
    return (days.contains(now.weekday) && minute >= startMinute) ||
        (days.contains(yesterday) && minute < endMinute);
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'days': [...days]..sort(),
        'start': formatClockTime(startMinute),
        'end': formatClockTime(endMinute),
        'priority': priority,
        'target': target,
        'items': [for (final item in items) item.toJson()],
      };
}

/// Resolução da agenda sobre um [ContentManifest].
extension ScheduleResolution on ContentManifest {
  /// A primeira regra de [ContentManifest.schedules] ativa em [now].
  ///
  /// O servidor manda as regras já na ordem de precedência.
  ScheduleRule? activeScheduleAt(DateTime now) {
    for (final rule in schedules) {
      if (rule.isActiveAt(now)) return rule;
    }
    return null;
  }

  /// O que a TV deve exibir em [now]: os itens da regra ativa ou, sem
  /// nenhuma, os [ContentManifest.items] padrão.
  List<ContentItem> itemsAt(DateTime now) =>
      activeScheduleAt(now)?.items ?? items;

  /// Todos os itens que podem ser exibidos, para baixar com antecedência.
  Iterable<ContentItem> get allItems sync* {
    yield* items;
    for (final rule in schedules) {
      yield* rule.items;
    }
  }

  /// Próximo início ou fim de faixa depois de [now], quando a TV precisa
  /// recalcular o que exibe. `null` sem agendamentos.
  DateTime? nextChangeAfter(DateTime now) {
    if (schedules.isEmpty) return null;
    final boundaries = {
      for (final rule in schedules) ...[rule.startMinute, rule.endMinute],
    };
    DateTime? next;
    for (var day = 0; day <= 1; day++) {
      for (final minute in boundaries) {
        final candidate = DateTime(
          now.year,
          now.month,
          now.day + day,
          minute ~/ 60,
          minute % 60,
        );
        if (candidate.isAfter(now) &&
            (next == null || candidate.isBefore(next))) {
          next = candidate;
        }
      }
    }
    return next;
  }
}
