import 'dart:async';

import 'package:flutter/services.dart';

/// Teclas de OK do controle remoto.
final Set<LogicalKeyboardKey> selectKeys = {
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.gameButtonA,
};

/// Detecta os gestos que abrem o menu oculto: ⬆ ⬆ ⬇ ⬇ em até [window], ou
/// OK segurado por [holdFor]. Lógica pura: o relógio é injetado e o único
/// timer é o do OK segurado.
class MenuTrigger {
  MenuTrigger({
    required this.onOpen,
    DateTime Function()? now,
    this.window = const Duration(seconds: 3),
    this.holdFor = const Duration(seconds: 2),
  }) : _now = now ?? DateTime.now;

  /// Chamado ao reconhecer um gesto; `byHold` é `true` para o OK segurado.
  final void Function({required bool byHold}) onOpen;
  final DateTime Function() _now;
  final Duration window;
  final Duration holdFor;

  static final _sequence = [
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowDown,
  ];

  int _progress = 0;
  DateTime _sequenceStart = DateTime.fromMillisecondsSinceEpoch(0);
  LogicalKeyboardKey? _held;
  DateTime _heldSince = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _holdTimer;

  /// Alimenta o detector com um evento de teclado.
  void onKeyEvent(KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyUpEvent) {
      if (key == _held) _cancelHold();
      return;
    }
    if (selectKeys.contains(key)) {
      _progress = 0;
      if (event is KeyDownEvent && _held == null) {
        _held = key;
        _heldSince = _now();
        _holdTimer = Timer(holdFor, () => _openByHold(key));
      } else if (event is KeyRepeatEvent && key == _held) {
        // Controles que repetem a tecla: confere o tempo sem esperar o timer.
        if (_now().difference(_heldSince) >= holdFor) _openByHold(key);
      }
      return;
    }
    if (event is! KeyDownEvent) return;
    _onSequenceKey(key);
  }

  void _onSequenceKey(LogicalKeyboardKey key) {
    final now = _now();
    if (_progress > 0 && now.difference(_sequenceStart) > window) {
      _progress = 0;
    }
    if (key == _sequence[_progress]) {
      if (_progress == 0) _sequenceStart = now;
      _progress++;
    } else if (key == _sequence.first) {
      _progress = 1;
      _sequenceStart = now;
    } else {
      _progress = 0;
    }
    if (_progress == _sequence.length) {
      _progress = 0;
      onOpen(byHold: false);
    }
  }

  void _openByHold(LogicalKeyboardKey key) {
    if (_held != key) return;
    _cancelHold();
    onOpen(byHold: true);
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _held = null;
  }

  /// Esquece o gesto em andamento.
  void reset() {
    _progress = 0;
    _cancelHold();
  }

  void dispose() => _cancelHold();
}
