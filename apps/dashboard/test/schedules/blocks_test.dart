import 'package:beyond_dashboard/src/api/schedules.dart';
import 'package:beyond_dashboard/src/schedules/schedule_blocks.dart';
import 'package:flutter_test/flutter_test.dart';

Schedule rule(Set<int> days, int start, int end) => Schedule(
      id: 's',
      name: 'Teste',
      playlistId: 'p',
      groupId: 1,
      days: days,
      startMinute: start,
      endMinute: end,
      priority: 0,
      createdAt: DateTime.utc(2026, 10, 1),
    );

List<(int, int, int)> spans(Schedule s) => [
      for (final b in blocksFor(s)) (b.day, b.startMinute, b.endMinute),
    ];

void main() {
  test('faixa normal fica num bloco por dia', () {
    expect(spans(rule({2}, 11 * 60, 14 * 60)), [(2, 660, 840)]);
  });

  test('faixa que vira a noite se divide no dia seguinte', () {
    expect(
      spans(rule({3}, 22 * 60, 6 * 60)),
      [(3, 1320, 1440), (4, 0, 360)],
    );
  });

  test('domingo vira a noite e volta para segunda', () {
    expect(
      spans(rule({7}, 22 * 60, 2 * 60)),
      [(1, 0, 120), (7, 1320, 1440)],
    );
  });

  test('fim à meia-noite não gera bloco vazio no dia seguinte', () {
    expect(spans(rule({1}, 22 * 60, 0)), [(1, 1320, 1440)]);
  });

  test('24 h a partir da meia-noite ocupa o dia inteiro', () {
    expect(spans(rule({5}, 0, 0)), [(5, 0, 1440)]);
  });

  test('24 h a partir das 08:00 termina às 08:00 do dia seguinte', () {
    expect(
      spans(rule({5}, 8 * 60, 8 * 60)),
      [(5, 480, 1440), (6, 0, 480)],
    );
  });

  test('vários dias geram blocos ordenados por dia', () {
    expect(
      spans(rule({5, 1, 3}, 9 * 60, 10 * 60)),
      [(1, 540, 600), (3, 540, 600), (5, 540, 600)],
    );
  });
}
