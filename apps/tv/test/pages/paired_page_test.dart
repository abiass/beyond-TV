import 'dart:math';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_tv/src/device/credentials.dart';
import 'package:beyond_tv/src/pages/paired_page.dart';
import 'package:beyond_tv/src/realtime/backoff.dart';
import 'package:beyond_tv/src/realtime/device_connection.dart';
import 'package:beyond_tv/src/server/server_address.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';
import '../support/fakes.dart';

const _credentials = Credentials(
  deviceId: 'tv-1',
  deviceToken: 'segredo',
  server: pcSala,
);

void main() {
  late FakeConnector connector;

  DeviceConnection make([Credentials credentials = _credentials]) {
    return DeviceConnection(
      credentials: credentials,
      deviceInfo: const FakeDeviceInfo(),
      store: MemoryCredentialStore(credentials),
      connector: connector.call,
      backoff: Backoff(
        initial: const Duration(seconds: 10),
        max: const Duration(seconds: 10),
        random: Random(1),
      ),
    );
  }

  Future<void> show(WidgetTester tester, DeviceConnection connection) async {
    useTvScreen(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ListenableBuilder(
          listenable: connection,
          builder: (_, __) => PairedPage(connection: connection),
        ),
      ),
    );
  }

  /// Tira a página e encerra a conexão para não sobrar timer pendente.
  Future<void> finish(WidgetTester tester, DeviceConnection c) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(c.dispose);
  }

  setUp(() => connector = FakeConnector());

  testWidgets('mostra título, subtítulo e o aviso de conteúdo', (tester) async {
    final connection = make()..start();
    await show(tester, connection);
    await tester.pump();

    expect(find.text('TV pareada!'), findsOneWidget);
    expect(
      find.text('Conectada a PC-SALA · 192.168.0.10:8787'),
      findsOneWidget,
    );
    expect(find.textContaining('Aguardando conteúdo'), findsOneWidget);
    await finish(tester, connection);
  });

  testWidgets('sem nome do servidor, o subtítulo diz "servidor"',
      (tester) async {
    final connection = make(
      const Credentials(
        deviceId: 'tv-1',
        deviceToken: 'segredo',
        server: ServerAddress(host: '192.168.0.10'),
      ),
    )..start();
    await show(tester, connection);
    await tester.pump();

    expect(
      find.text('Conectada a servidor · 192.168.0.10:8787'),
      findsOneWidget,
    );
    await finish(tester, connection);
  });

  testWidgets('conectando: aparece antes de a conexão responder',
      (tester) async {
    final connection = make();
    await show(tester, connection);

    expect(connection.status, ConnectionStatus.connecting);
    expect(find.text('Conectando…'), findsOneWidget);
    expect(find.byIcon(Icons.circle), findsNothing);
    await finish(tester, connection);
  });

  testWidgets('online: texto e ícone verde', (tester) async {
    final connection = make()..start();
    await show(tester, connection);
    await tester.pump();

    expect(connection.status, ConnectionStatus.online);
    expect(find.text('Conectada'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.circle));
    expect(icon.color, Colors.green);
    await finish(tester, connection);
  });

  testWidgets('offline: mostra os segundos até a próxima tentativa',
      (tester) async {
    connector.failures = 1;
    final connection = make()..start();
    await show(tester, connection);
    await tester.pump();

    expect(connection.status, ConnectionStatus.offline);
    final seconds = (connection.nextRetryIn!.inMilliseconds / 1000).ceil();
    expect(
      find.text('Sem conexão com o servidor. Tentando de novo em $seconds s.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.circle), findsNothing);
    await finish(tester, connection);
  });

  const closed = {
    WsCloseCodes.replaced: (
      ConnectionStatus.replaced,
      'Esta TV foi aberta em outro lugar.',
    ),
    WsCloseCodes.incompatibleVersion: (
      ConnectionStatus.outdated,
      'Atualize o app da TV.',
    ),
    WsCloseCodes.unauthorized: (
      ConnectionStatus.unauthorized,
      'Esta TV foi removida do painel.',
    ),
  };

  for (final MapEntry(key: code, value: (status, text)) in closed.entries) {
    testWidgets('fechada com $code: $status', (tester) async {
      final connection = make()..start();
      await show(tester, connection);
      await tester.pump();

      connector.last.serverClose(code);
      await tester.pump();
      await tester.pump();

      expect(connection.status, status);
      expect(find.text(text), findsOneWidget);
      await finish(tester, connection);
    });
  }
}
