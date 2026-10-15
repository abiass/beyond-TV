import 'dart:math';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_server/server.dart';
import 'package:test/test.dart';

import '../support/test_server.dart';

void main() {
  const info = DeviceInfo(appVersion: '1.1.0');
  late FakeClock clock;
  late PairRequestStore store;

  setUp(() {
    clock = FakeClock();
    store = PairRequestStore(clock: clock.call, maxPending: 3);
  });

  test('códigos de conferência não se repetem entre pedidos abertos', () {
    // Sorteia 7, 7 e 9: o segundo pedido precisa pular o 7, já em uso.
    store = PairRequestStore(clock: clock.call, random: _Repeating([7, 7, 9]));

    final (a, _, _) = store.create(info, '10.0.0.1');
    final (b, _, _) = store.create(info, '10.0.0.2');

    expect(a.confirmCode, '0007');
    expect(b.confirmCode, '0009');
  });

  test('recusa acima do limite de pedidos abertos', () {
    for (var i = 1; i <= 3; i++) {
      store.create(info, '10.0.0.$i');
    }

    expect(
      () => store.create(info, '10.0.0.9'),
      throwsA(isA<TooManyPairRequests>()),
    );
  });

  test('pedidos vencidos não contam no limite e saem da lista', () {
    for (var i = 1; i <= 3; i++) {
      store.create(info, '10.0.0.$i');
    }
    clock.advance(pairRequestTtl);

    expect(store.pending(), isEmpty);
    expect(() => store.create(info, '10.0.0.9'), returnsNormally);
  });

  test('esquece o pedido um período depois de vencer', () {
    final (ticket, _, _) = store.create(info, '10.0.0.1');

    clock.advance(pairRequestTtl * 2 + const Duration(seconds: 1));

    expect(store.findForTv(ticket.id, ticket.secret), isNull);
  });

  test('a lista sai do mais antigo para o mais novo', () {
    store.create(info, '10.0.0.1');
    clock.advance(const Duration(seconds: 5));
    store.create(info, '10.0.0.2');

    expect([for (final p in store.pending()) p.ip], ['10.0.0.1', '10.0.0.2']);
  });
}

/// [Random] que devolve [values] em sequência em `nextInt`.
class _Repeating implements Random {
  _Repeating(this.values);

  final List<int> values;
  var _i = 0;

  @override
  int nextInt(int max) => values[_i++ % values.length];

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();
}
