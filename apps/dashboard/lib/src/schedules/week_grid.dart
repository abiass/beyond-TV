import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/material.dart';

import '../api/schedules.dart';
import 'schedule_blocks.dart';
import 'schedule_format.dart';

const _hourHeight = 28.0;
const _timeColumn = 44.0;
const _palette = [
  Color(0xFF1565C0),
  Color(0xFF2E7D32),
  Color(0xFFC62828),
  Color(0xFF6A1B9A),
  Color(0xFFEF6C00),
  Color(0xFF00838F),
  Color(0xFF4E342E),
  Color(0xFFAD1457),
];

/// Cor do agendamento na posição [index] da lista.
Color scheduleColor(int index) => _palette[index % _palette.length];

/// Grade semanal: 7 colunas (Seg a Dom) por 24 horas, com um bloco por trecho
/// de agendamento. Toque num bloco chama [onTap].
class WeekGrid extends StatelessWidget {
  const WeekGrid({required this.schedules, required this.onTap, super.key});

  final List<Schedule> schedules;
  final void Function(Schedule schedule) onTap;

  @override
  Widget build(BuildContext context) {
    final blocksByDay = <int, List<ScheduleBlock>>{
      for (final day in dayLabels.keys) day: [],
    };
    for (final schedule in schedules) {
      for (final block in blocksFor(schedule)) {
        blocksByDay[block.day]!.add(block);
      }
    }
    final line = Theme.of(context).dividerColor;

    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: _timeColumn),
            for (final label in dayLabels.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _timeColumn,
              height: 24 * _hourHeight,
              child: Stack(
                children: [
                  for (var h = 0; h < 24; h += 2)
                    Positioned(
                      top: h * _hourHeight - 1,
                      right: 6,
                      child: Text(
                        formatClockTime(h * 60),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                ],
              ),
            ),
            for (final day in dayLabels.keys)
              Expanded(
                child: _DayColumn(
                  blocks: blocksByDay[day]!,
                  schedules: schedules,
                  lineColor: line,
                  onTap: onTap,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.blocks,
    required this.schedules,
    required this.lineColor,
    required this.onTap,
  });

  final List<ScheduleBlock> blocks;
  final List<Schedule> schedules;
  final Color lineColor;
  final void Function(Schedule schedule) onTap;

  /// Faixa (lane) de cada bloco, para que blocos que se sobrepõem fiquem
  /// lado a lado. Devolve as faixas e quantas existem.
  (List<int>, int) _lanes() {
    final ends = <int>[];
    final lanes = <int>[];
    for (final block in blocks) {
      var lane = ends.indexWhere((end) => end <= block.startMinute);
      if (lane < 0) {
        lane = ends.length;
        ends.add(block.endMinute);
      } else {
        ends[lane] = block.endMinute;
      }
      lanes.add(lane);
    }
    return (lanes, ends.length);
  }

  @override
  Widget build(BuildContext context) {
    final (lanes, laneCount) = _lanes();

    return Container(
      height: 24 * _hourHeight,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: lineColor)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final laneWidth =
              constraints.maxWidth / (laneCount == 0 ? 1 : laneCount);
          return Stack(
            children: [
              for (var h = 0; h < 24; h++)
                Positioned(
                  top: h * _hourHeight,
                  left: 0,
                  right: 0,
                  child: Divider(height: 1, color: lineColor),
                ),
              for (var i = 0; i < blocks.length; i++)
                _positioned(context, blocks[i], lanes[i], laneWidth),
            ],
          );
        },
      ),
    );
  }

  Widget _positioned(
    BuildContext context,
    ScheduleBlock block,
    int lane,
    double laneWidth,
  ) {
    final schedule = block.schedule;
    final index = schedules.indexWhere((s) => s.id == schedule.id);
    final times = describeTimes(schedule);
    return Positioned(
      key: ValueKey(
        'block-${schedule.id}-${block.day}-${block.startMinute}',
      ),
      top: block.startMinute / 60 * _hourHeight,
      height: (block.endMinute - block.startMinute) / 60 * _hourHeight - 1,
      left: lane * laneWidth + 1,
      width: laneWidth - 2,
      child: Tooltip(
        message: '${schedule.name}\n$times',
        child: Material(
          color: scheduleColor(index < 0 ? 0 : index).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => onTap(schedule),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: ClipRect(
                child: Text(
                  '${schedule.name}\n$times',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
