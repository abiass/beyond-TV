import 'package:flutter/material.dart';

import '../api/schedules.dart';
import 'schedule_format.dart';

/// Linha de resumo de um agendamento (nome, dias, horário e prioridade).
class ScheduleSummaryTile extends StatelessWidget {
  const ScheduleSummaryTile(this.schedule, {this.origin, super.key});

  final Schedule schedule;

  /// De onde vem: "TV" ou "Grupo", quando a lista mistura os dois.
  final String? origin;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: const Icon(Icons.schedule),
        title:
            Text(origin == null ? schedule.name : '${schedule.name} ($origin)'),
        subtitle: Text(describeSchedule(schedule)),
      );
}
