import 'dart:math';

import 'package:beyond_tv/src/realtime/backoff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cresce em dobro e satura em 60 s, com ±20%', () {
    final backoff = Backoff(random: Random(7));
    final expected = [1, 2, 4, 8, 16, 32, 60, 60, 60];
    for (final seconds in expected) {
      final ms = backoff.next().inMilliseconds;
      expect(ms, inInclusiveRange(seconds * 800, seconds * 1200));
    }
    expect(backoff.failures, expected.length);
  });

  test('reset volta para 1 s', () {
    final backoff = Backoff(random: Random(1));
    for (var i = 0; i < 5; i++) {
      backoff.next();
    }
    backoff.reset();
    expect(backoff.failures, 0);
    expect(backoff.next().inMilliseconds, inInclusiveRange(800, 1200));
  });

  test('não estoura com muitas falhas', () {
    final backoff = Backoff(random: Random(3));
    for (var i = 0; i < 200; i++) {
      backoff.next();
    }
    expect(backoff.next().inSeconds, lessThanOrEqualTo(72));
  });
}
