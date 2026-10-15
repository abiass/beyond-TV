import 'dart:math';

/// Espera crescente entre tentativas de reconexão: 1 s, 2 s, 4 s… até [max],
/// com variação aleatória de ±[jitter].
class Backoff {
  Backoff({
    this.initial = const Duration(seconds: 1),
    this.max = const Duration(seconds: 60),
    this.jitter = 0.2,
    Random? random,
  }) : _random = random ?? Random();

  final Duration initial;
  final Duration max;
  final double jitter;
  final Random _random;

  int _failures = 0;

  /// Falhas seguidas desde o último [reset].
  int get failures => _failures;

  /// Espera antes da próxima tentativa; conta mais uma falha.
  Duration next() {
    final base = initial.inMicroseconds * pow(2, min(_failures, 30));
    final capped = min(base, max.inMicroseconds.toDouble());
    _failures++;
    final factor = 1 + (_random.nextDouble() * 2 - 1) * jitter;
    return Duration(microseconds: (capped * factor).round());
  }

  void reset() => _failures = 0;
}
