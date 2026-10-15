import 'package:beyond_dashboard/src/realtime/admin_events.dart';
import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_admin_socket.dart';

/// Canal cujo `ready` falha, como um servidor fora do ar.
class _FailingSocket extends FakeAdminSocket {
  @override
  Future<void> get ready => Future<void>.error(StateError('sem conexão'));
}

/// Entrega um canal por chamada: o próximo da fila, ou um que falha.
class _Connector {
  _Connector([List<FakeAdminSocket> queue = const []]) : _queue = [...queue];

  final List<FakeAdminSocket> _queue;
  final uris = <Uri>[];

  int get calls => uris.length;

  FakeAdminSocket call(Uri uri) {
    uris.add(uri);
    return _queue.isEmpty ? _FailingSocket() : _queue.removeAt(0);
  }
}

Envelope _removed(String id) =>
    Envelope.create(MessageTypes.deviceRemoved, payload: {'deviceId': id});

void main() {
  final uri = Uri.parse('ws://192.168.0.10:8787/ws/admin');

  group('adminSocketUri', () {
    test('troca http por ws e mantém a porta', () {
      expect(
        adminSocketUri(Uri.parse('http://192.168.0.10:8787')).toString(),
        'ws://192.168.0.10:8787/ws/admin',
      );
    });

    test('troca https por wss sem inventar porta', () {
      expect(
        adminSocketUri(Uri.parse('https://example.local')).toString(),
        'wss://example.local/ws/admin',
      );
    });
  });

  test('backoff dobra até 16s e fica em 30s', () {
    final seconds = [0, 1, 2, 3, 4, 5, 10]
        .map((a) => AdminEvents.backoff(a).inSeconds)
        .toList();
    expect(seconds, [1, 2, 4, 8, 16, 30, 30]);
  });

  group('AdminEvents', () {
    late _Connector connector;
    late AdminEvents events;
    late int unauthorized;

    AdminEvents build(_Connector c) {
      connector = c;
      unauthorized = 0;
      events = AdminEvents(
        uri: uri,
        connector: c.call,
        onUnauthorized: () => unauthorized++,
      );
      addTearDown(events.dispose);
      return events;
    }

    // Descarta o canal ao fim: o teste de widget exige zero timers pendentes.
    void testEvents(String name, Future<void> Function(WidgetTester) body) =>
        testWidgets(name, (tester) async {
          await body(tester);
          events.dispose();
        });

    testEvents('conecta, marca conectado e repassa eventos', (tester) async {
      final socket = FakeAdminSocket();
      build(_Connector([socket]));
      final received = <Envelope>[];
      final states = <bool>[];
      events.events.listen(received.add);
      events.connected.listen(states.add);

      events.start();
      await tester.pump();
      final sent = _removed('tv-1');
      socket.emit(sent);
      await tester.pump();

      expect(connector.uris, [uri]);
      expect(states, [false, true]);
      expect(received.single.id, sent.id);
      expect(received.single.payload['deviceId'], 'tv-1');
    });

    testEvents('ignora mensagem inválida e não-String', (tester) async {
      final socket = FakeAdminSocket();
      build(_Connector([socket]));
      final received = <Envelope>[];
      events.events.listen(received.add);

      events.start();
      await tester.pump();
      socket
        ..emitRaw('isto não é um envelope')
        ..emitRaw(<int>[1, 2, 3])
        ..emitRaw(42)
        ..emit(_removed('tv-2'));
      await tester.pump();

      expect(received, hasLength(1));
      expect(received.single.payload['deviceId'], 'tv-2');
    });

    testEvents('queda comum reconecta com 1s, 2s e 4s de espera',
        (tester) async {
      final first = FakeAdminSocket();
      final states = <bool>[];
      build(_Connector([first]));
      events.connected.listen(states.add);

      events.start();
      await tester.pump();
      first.closeWith(1006);
      await tester.pump();
      expect(states, [false, true, false]);
      expect(connector.calls, 1);

      await tester.pump(const Duration(milliseconds: 999));
      expect(connector.calls, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(connector.calls, 2);

      // A segunda tentativa falha: espera 2s, depois 4s.
      await tester.pump(const Duration(seconds: 1));
      expect(connector.calls, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(connector.calls, 3);
      await tester.pump(const Duration(seconds: 3));
      expect(connector.calls, 3);
      await tester.pump(const Duration(seconds: 1));
      expect(connector.calls, 4);
    });

    testEvents('conexão com sucesso zera o contador de tentativas',
        (tester) async {
      final first = FakeAdminSocket();
      final second = FakeAdminSocket();
      build(_Connector([first, _FailingSocket(), _FailingSocket(), second]));

      events.start();
      await tester.pump();
      first.closeWith(1006);
      await tester.pump();
      // 1s + 2s + 4s até a quarta chamada conectar.
      await tester.pump(const Duration(seconds: 7));
      expect(connector.calls, 4);

      second.closeWith(1006);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(connector.calls, 5);
    });

    testEvents('401 avisa uma vez e nunca mais reconecta', (tester) async {
      final socket = FakeAdminSocket();
      final states = <bool>[];
      build(_Connector([socket]));
      events.connected.listen(states.add);

      events.start();
      await tester.pump();
      socket.closeWith(WsCloseCodes.unauthorized);
      await tester.pump();
      await tester.pump(const Duration(seconds: 60));

      expect(unauthorized, 1);
      expect(connector.calls, 1);
      expect(states.last, isFalse);
    });

    testEvents('falha no ready agenda nova tentativa', (tester) async {
      build(_Connector());
      final states = <bool>[];
      events.connected.listen(states.add);

      events.start();
      await tester.pump();
      expect(connector.calls, 1);

      await tester.pump(const Duration(seconds: 1));
      expect(connector.calls, 2);
      expect(states, [false]);
    });

    testEvents('start repetido com conexão aberta não abre outra',
        (tester) async {
      build(_Connector([FakeAdminSocket()]));

      events.start();
      await tester.pump();
      events
        ..start()
        ..start();
      await tester.pump();

      expect(connector.calls, 1);
    });

    testEvents('start repetido durante a conexão não abre outra',
        (tester) async {
      build(_Connector([FakeAdminSocket()]));

      events
        ..start()
        ..start();
      await tester.pump();

      expect(connector.calls, 1);
    });

    testEvents('dispose cancela a tentativa pendente', (tester) async {
      build(_Connector());

      events.start();
      await tester.pump();
      expect(connector.calls, 1);

      events.dispose();
      await tester.pump(const Duration(seconds: 60));

      expect(connector.calls, 1);
    });

    testEvents('connected assinado depois emite o valor atual', (tester) async {
      build(_Connector([FakeAdminSocket()]));

      events.start();
      await tester.pump();

      final states = <bool>[];
      events.connected.listen(states.add);
      await tester.pump();

      expect(states, [true]);
    });
  });
}
