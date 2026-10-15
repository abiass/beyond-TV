import 'package:flutter/foundation.dart';

/// Últimas linhas de log do app, para o menu oculto. Nunca recebe token.
class AppLog extends ChangeNotifier {
  AppLog({this.capacity = 50, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  /// Log do app inteiro.
  static final AppLog instance = AppLog();

  final int capacity;
  final DateTime Function() _now;
  final List<String> _lines = [];

  /// Da mais antiga para a mais nova, cada uma com o horário.
  List<String> get lines => List.unmodifiable(_lines);

  void add(String message) {
    final t = _now();
    String two(int v) => v.toString().padLeft(2, '0');
    _lines.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)} $message');
    if (_lines.length > capacity) _lines.removeAt(0);
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }
}

/// Registra [message] no log do app e no console de depuração.
void appLog(String message) {
  debugPrint(message);
  AppLog.instance.add(message);
}
