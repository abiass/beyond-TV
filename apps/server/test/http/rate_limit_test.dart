import 'package:beyond_server/server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../support/test_server.dart';

void main() {
  late FakeClock clock;
  late RateLimiter limiter;

  setUp(() {
    clock = FakeClock();
    limiter = RateLimiter(
      maxAttempts: 3,
      window: const Duration(minutes: 1),
      clock: clock.call,
    );
  });

  test('libera até o limite e depois informa quanto esperar', () {
    for (var i = 0; i < 3; i++) {
      expect(limiter.retryAfter('ip'), isNull);
      limiter.hit('ip');
      clock.advance(const Duration(seconds: 10));
    }

    expect(limiter.retryAfter('ip'), const Duration(seconds: 30));
  });

  test('a janela desliza: a tentativa mais antiga expira primeiro', () {
    for (var i = 0; i < 3; i++) {
      limiter.hit('ip');
      clock.advance(const Duration(seconds: 10));
    }

    clock.advance(const Duration(seconds: 30));
    expect(limiter.retryAfter('ip'), isNull);
    limiter.hit('ip');
    expect(limiter.retryAfter('ip'), const Duration(seconds: 10));
  });

  test('cada chave tem o próprio contador', () {
    for (var i = 0; i < 3; i++) {
      limiter.hit('a');
    }

    expect(limiter.retryAfter('a'), isNotNull);
    expect(limiter.retryAfter('b'), isNull);
  });

  test('reset esquece as tentativas', () {
    for (var i = 0; i < 3; i++) {
      limiter.hit('ip');
    }

    limiter.reset('ip');

    expect(limiter.retryAfter('ip'), isNull);
  });

  test('consume lança 429 com Retry-After arredondado para cima', () {
    for (var i = 0; i < 3; i++) {
      limiter.consume('ip');
    }
    clock.advance(const Duration(milliseconds: 500));

    late Response response;
    try {
      limiter.consume('ip');
      fail('deveria ter lançado');
    } on TooManyRequestsException catch (e) {
      response = e.toResponse();
    }

    expect(response.statusCode, 429);
    expect(response.headers['retry-after'], '60');
  });
}
