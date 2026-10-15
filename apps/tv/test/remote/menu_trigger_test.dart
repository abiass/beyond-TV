import 'package:fake_async/fake_async.dart';
import 'package:beyond_tv/src/remote/menu_trigger.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

KeyDownEvent _down(LogicalKeyboardKey key) => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyA,
      logicalKey: key,
      timeStamp: Duration.zero,
    );

KeyUpEvent _up(LogicalKeyboardKey key) => KeyUpEvent(
      physicalKey: PhysicalKeyboardKey.keyA,
      logicalKey: key,
      timeStamp: Duration.zero,
    );

KeyRepeatEvent _repeat(LogicalKeyboardKey key) => KeyRepeatEvent(
      physicalKey: PhysicalKeyboardKey.keyA,
      logicalKey: key,
      timeStamp: Duration.zero,
    );

void main() {
  final up = LogicalKeyboardKey.arrowUp;
  final down = LogicalKeyboardKey.arrowDown;
  late DateTime clock;
  late List<bool> opened;
  late MenuTrigger trigger;

  setUp(() {
    clock = DateTime(2026, 10, 15, 12);
    opened = [];
    trigger = MenuTrigger(
      onOpen: ({required byHold}) => opened.add(byHold),
      now: () => clock,
    );
  });

  tearDown(() => trigger.dispose());

  void press(LogicalKeyboardKey key, [int afterMs = 100]) {
    clock = clock.add(Duration(milliseconds: afterMs));
    trigger.onKeyEvent(_down(key));
    trigger.onKeyEvent(_up(key));
  }

  test('⬆ ⬆ ⬇ ⬇ dentro de 3 s abre', () {
    press(up);
    press(up);
    press(down);
    expect(opened, isEmpty);
    press(down);
    expect(opened, [false]);
  });

  test('sequência lenta demais não abre', () {
    press(up);
    press(up);
    press(down);
    press(down, 3000);
    expect(opened, isEmpty);
  });

  test('sequência errada reinicia', () {
    press(up);
    press(down);
    press(up);
    press(down);
    expect(opened, isEmpty);
    // Recomeça do zero depois do erro.
    press(up);
    press(up);
    press(down);
    press(down);
    expect(opened, [false]);
  });

  test('outra tecla no meio reinicia', () {
    press(up);
    press(up);
    press(LogicalKeyboardKey.arrowLeft);
    press(down);
    press(down);
    expect(opened, isEmpty);
  });

  test('o primeiro ⬆ de uma tentativa errada já conta como início', () {
    press(up);
    press(up);
    press(up);
    press(up);
    press(down);
    press(down);
    expect(opened, [false]);
  });

  test('OK segurado por 2 s abre (timer)', () {
    fakeAsync((async) {
      trigger.onKeyEvent(_down(LogicalKeyboardKey.select));
      async.elapse(const Duration(milliseconds: 1999));
      expect(opened, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(opened, [true]);
    });
  });

  test('soltar o OK antes de 2 s não abre', () {
    fakeAsync((async) {
      trigger.onKeyEvent(_down(LogicalKeyboardKey.enter));
      async.elapse(const Duration(seconds: 1));
      trigger.onKeyEvent(_up(LogicalKeyboardKey.enter));
      async.elapse(const Duration(seconds: 5));
      expect(opened, isEmpty);
    });
  });

  test('OK com repeat abre pelo relógio, sem esperar o timer', () {
    fakeAsync((async) {
      trigger.onKeyEvent(_down(LogicalKeyboardKey.gameButtonA));
      clock = clock.add(const Duration(milliseconds: 1500));
      trigger.onKeyEvent(_repeat(LogicalKeyboardKey.gameButtonA));
      expect(opened, isEmpty);
      clock = clock.add(const Duration(milliseconds: 600));
      trigger.onKeyEvent(_repeat(LogicalKeyboardKey.gameButtonA));
      expect(opened, [true]);
      async.elapse(const Duration(seconds: 5));
      expect(opened, [true]);
    });
  });
}
