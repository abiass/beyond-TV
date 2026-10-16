import 'package:beyond_dashboard/src/api/api_client.dart';
import 'package:beyond_dashboard/src/auth/auth_controller.dart';
import 'package:beyond_dashboard/src/devices/live_control_page.dart';
import 'package:beyond_dashboard/src/realtime/admin_events.dart';
import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_admin_socket.dart';
import '../support/fake_api.dart';

void main() {
  late FakeApi api;
  late FakeAdminSocket socket;

  setUp(() {
    api = FakeApi(adminPassword: 'x', loggedIn: true)
      ..devices.add(
        DeviceSummary(
          id: 'a',
          name: 'Recepção',
          online: true,
          createdAt: DateTime.utc(2026, 10, 1),
        ),
      );
    socket = FakeAdminSocket();
  });

  Future<void> open(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1600, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          adminSocketConnectorProvider.overrideWithValue((_) => socket),
        ],
        child: const MaterialApp(home: LiveControlPage(id: 'a')),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  void frame(DateTime at) => socket.emit(
        Envelope.create(
          MessageTypes.deviceScreenshot,
          payload:
              DeviceScreenshotEvent(deviceId: 'a', capturedAt: at).toJson(),
        ),
      );

  /// Área da imagem da TV (o quadro 16:9).
  Finder screen() => find.byType(AspectRatio);

  /// Deixa a fila de envios andar.
  Future<void> flush(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
  }

  testWidgets('abre o controle e pede quadros', (tester) async {
    await open(tester);

    expect(api.liveStarted, ['a']);
    expect(api.liveFrames, 1);
    expect(find.text('Controlar Recepção'), findsOneWidget);

    frame(DateTime.utc(2026, 10, 16, 12));
    await tester.pump(liveFrameGap);

    // Recebeu um quadro: mostra a imagem e já pede o próximo.
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as NetworkImage).url,
      contains('/api/v1/devices/a/screenshot'),
    );
    expect(api.liveFrames, 2);
  });

  testWidgets('sem quadro em 5 s, pede de novo', (tester) async {
    await open(tester);

    await tester.pump(liveFrameWait);

    expect(api.liveFrames, 2);
  });

  testWidgets('clique vira toque na mesma posição da TV', (tester) async {
    await open(tester);
    final box = tester.getRect(screen());

    await tester.tapAt(box.topLeft + Offset(box.width / 4, box.height * 3 / 4));
    await flush(tester);

    final tap = api.inputs.single;
    expect(tap.kind, RemoteInputKind.tap);
    expect(tap.x, closeTo(0.25, 0.01));
    expect(tap.y, closeTo(0.75, 0.01));
  });

  testWidgets('digitação vai em lote e as teclas em ordem', (tester) async {
    await open(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA, character: 'a');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB, character: 'b');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await flush(tester);

    expect([
      for (final i in api.inputs) i.toJson(),
    ], [
      {'kind': 'text', 'text': 'ab'},
      {'kind': 'key', 'key': 'enter'},
    ]);
  });

  testWidgets('Shift+Tab volta um campo', (tester) async {
    await open(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await flush(tester);

    expect(api.inputs.single.key, RemoteKeys.shiftTab);
  });

  testWidgets('roda do mouse rola a página da TV', (tester) async {
    await open(tester);
    final center = tester.getCenter(screen());
    final pointer = TestPointer(1, PointerDeviceKind.mouse);

    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 300)));
    await flush(tester);

    final scroll = api.inputs.single;
    expect(scroll.kind, RemoteInputKind.scroll);
    expect(scroll.dy, greaterThan(0));
  });

  testWidgets('mostra o motivo quando a TV não executa', (tester) async {
    await open(tester);

    socket.emit(
      Envelope.create(
        MessageTypes.deviceInputError,
        payload: {
          'deviceId': 'a',
          'code': 'input_failed',
          'message': 'Nenhum campo de texto selecionado.',
        },
      ),
    );
    await tester.pump();

    expect(find.text('Nenhum campo de texto selecionado.'), findsOneWidget);
  });

  testWidgets('TV offline: avisa e tenta de novo', (tester) async {
    api.liveError = const ApiException(
      'A TV está offline.',
      code: 'device_offline',
      status: 409,
    );
    await open(tester);

    expect(find.text('A TV está offline.'), findsOneWidget);

    api.liveError = null;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(api.liveStarted, ['a']);
    expect(api.liveFrames, 1);
  });
}
