import 'package:beyond_dashboard/src/devices/format_relative.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 14, 12);

  String at(Duration ago) => formatRelative(now.subtract(ago), now);

  test('formata o tempo decorrido', () {
    expect(at(const Duration(seconds: 20)), 'agora há pouco');
    expect(at(const Duration(minutes: 5)), 'há 5 min');
    expect(at(const Duration(minutes: 59)), 'há 59 min');
    expect(at(const Duration(hours: 3)), 'há 3 h');
    expect(at(const Duration(days: 1)), 'há 1 dia');
    expect(at(const Duration(days: 2, hours: 5)), 'há 2 dias');
  });

  test('data no futuro conta como agora', () {
    expect(
      formatRelative(now.add(const Duration(minutes: 1)), now),
      'agora há pouco',
    );
  });
}
