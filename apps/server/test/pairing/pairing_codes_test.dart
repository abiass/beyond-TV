import 'dart:math';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_server/server.dart';
import 'package:test/test.dart';

import '../support/test_server.dart';

void main() {
  late FakeClock clock;
  late PairingCodeStore codes;

  setUp(() {
    clock = FakeClock();
    codes = PairingCodeStore(clock: clock.call);
  });

  test('gera códigos de 6 caracteres do alfabeto, válidos por 10 min', () {
    final code = codes.generate();

    expect(isWellFormedPairingCode(code.code), isTrue);
    expect(code.expiresAt, clock.now.add(const Duration(minutes: 10)));
    expect(codes.lookup(code.code)?.$2, PairingCodeStatus.pending);
  });

  test('não repete um código ainda guardado', () {
    // Com um Random de semente fixa, a mesma sequência se repetiria.
    codes = PairingCodeStore(clock: clock.call, random: _Repeating());

    final first = codes.generate().code;
    final second = codes.generate().code;

    expect(second, isNot(first));
  });

  test('o código vale uma única vez', () {
    final code = codes.generate().code;

    expect(codes.redeem(code, deviceId: 'tv1'), RedeemResult.ok);
    expect(codes.redeem(code, deviceId: 'tv2'), RedeemResult.invalid);

    final (entry, status) = codes.lookup(code)!;
    expect(status, PairingCodeStatus.paired);
    expect(entry.deviceId, 'tv1');
  });

  test('aceita o código digitado em minúsculas e com hífen', () {
    final code = codes.generate().code;
    final typed = '${code.substring(0, 3)}-${code.substring(3)}'.toLowerCase();

    expect(codes.redeem(typed, deviceId: 'tv1'), RedeemResult.ok);
  });

  test('expira depois de 10 minutos', () {
    final code = codes.generate().code;

    clock.advance(const Duration(minutes: 10) - const Duration(seconds: 1));
    expect(codes.lookup(code)?.$2, PairingCodeStatus.pending);

    clock.advance(const Duration(seconds: 1));
    expect(codes.lookup(code)?.$2, PairingCodeStatus.expired);
    expect(codes.redeem(code, deviceId: 'tv1'), RedeemResult.expired);
  });

  test('esquece o código 10 minutos depois de expirar', () {
    final code = codes.generate().code;

    clock.advance(const Duration(minutes: 20, seconds: 1));

    expect(codes.lookup(code), isNull);
    expect(codes.redeem(code, deviceId: 'tv1'), RedeemResult.invalid);
  });

  test('código inexistente é inválido', () {
    expect(codes.redeem('ZZZZZZ', deviceId: 'tv1'), RedeemResult.invalid);
  });
}

/// Devolve sempre a mesma sequência curta, para forçar colisões.
class _Repeating implements Random {
  var _calls = 0;

  @override
  int nextInt(int max) => (_calls++ ~/ pairingCodeLength) < 2 ? 0 : 1;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}
