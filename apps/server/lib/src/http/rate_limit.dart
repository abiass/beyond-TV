import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';

import '../clock.dart';
import 'json.dart';

/// Limita quantas tentativas cada chave (em geral, o IP) faz numa janela de
/// tempo deslizante.
///
/// Fica só em memória: reiniciar o servidor zera os contadores, o que é
/// aceitável para frear força bruta na LAN.
class RateLimiter {
  RateLimiter({
    required this.maxAttempts,
    required this.window,
    Clock clock = DateTime.now,
  }) : _clock = clock;

  final int maxAttempts;
  final Duration window;
  final Clock _clock;
  final _attempts = <String, List<DateTime>>{};

  /// Quanto falta para [key] poder tentar de novo, ou `null` se já pode.
  Duration? retryAfter(String key) {
    final attempts = _recent(key);
    if (attempts.length < maxAttempts) return null;
    return attempts.first.add(window).difference(_clock());
  }

  /// Registra uma tentativa de [key].
  void hit(String key) {
    if (_attempts.length > _maxKeys) _attempts.keys.toList().forEach(_recent);
    (_attempts[key] ??= []).add(_clock());
  }

  /// Esquece as tentativas de [key] (ex.: depois de um login certo).
  void reset(String key) => _attempts.remove(key);

  /// Lança [TooManyRequestsException] se [key] passou do limite; senão,
  /// registra a tentativa.
  void consume(String key) {
    check(key);
    hit(key);
  }

  /// Lança [TooManyRequestsException] se [key] passou do limite.
  void check(String key) {
    final wait = retryAfter(key);
    if (wait != null) throw TooManyRequestsException(wait);
  }

  /// Tentativas de [key] dentro da janela, descartando as antigas.
  List<DateTime> _recent(String key) {
    final attempts = _attempts[key];
    if (attempts == null) return const [];
    final start = _clock().subtract(window);
    attempts.removeWhere((time) => !time.isAfter(start));
    if (attempts.isEmpty) _attempts.remove(key);
    return attempts;
  }

  /// Acima disso, limpa as chaves antigas para a memória não crescer sem fim.
  static const _maxKeys = 10000;
}

/// Resposta `429` com o cabeçalho `Retry-After` em segundos.
class TooManyRequestsException extends ApiException {
  TooManyRequestsException(this.retryAfter)
    : super(
        429,
        'too_many_requests',
        'Muitas tentativas. Aguarde ${_seconds(retryAfter)} s e tente de novo.',
      );

  final Duration retryAfter;

  @override
  Response toResponse() => super.toResponse().change(
    headers: {'retry-after': '${_seconds(retryAfter)}'},
  );

  static int _seconds(Duration duration) =>
      max(1, (duration.inMilliseconds / 1000).ceil());
}

/// IP de quem fez a requisição, ou `unknown` fora do `shelf_io`.
String clientIp(Request request) =>
    switch (request.context['shelf.io.connection_info']) {
      final HttpConnectionInfo info => info.remoteAddress.address,
      _ => 'unknown',
    };
