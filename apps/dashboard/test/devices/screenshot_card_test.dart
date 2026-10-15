import 'package:beyond_dashboard/src/api/api_client.dart';
import 'package:beyond_dashboard/src/auth/auth_controller.dart';
import 'package:beyond_dashboard/src/devices/screenshot_card.dart';
import 'package:beyond_dashboard/src/realtime/admin_events.dart';
import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_admin_socket.dart';
import '../support/fake_api.dart';

DeviceSummary tv({bool online = true}) => DeviceSummary(
      id: 'a',
      name: 'Recepção',
      online: online,
      createdAt: DateTime.utc(2026, 10, 1),
    );

Envelope shotEvent(String deviceId, DateTime at) => Envelope.create(
      MessageTypes.deviceScreenshot,
      payload:
          DeviceScreenshotEvent(deviceId: deviceId, capturedAt: at).toJson(),
    );

void main() {
  late FakeApi api;
  late FakeAdminSocket socket;
  final at = DateTime.now().toUtc().subtract(const Duration(minutes: 2));

  setUp(() {
    api = FakeApi(adminPassword: 'x', loggedIn: true);
    socket = FakeAdminSocket();
  });

  Future<void> open(WidgetTester tester, {bool online = true}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          adminSocketConnectorProvider.overrideWithValue((_) => socket),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScreenshotCard(device: tv(online: online)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder button() => find.widgetWithText(OutlinedButton, 'Capturar tela');

  String? imageUrl(WidgetTester tester) {
    final image = find.byType(Image).evaluate().firstOrNull?.widget as Image?;
    return (image?.image as NetworkImage?)?.url;
  }

  testWidgets('captura, espera e mostra a imagem da TV certa', (tester) async {
    await open(tester);
    expect(find.byType(Image), findsNothing);

    await tester.tap(button());
    await tester.pump();
    expect(api.screenshotRequests, ['a']);
    expect(find.text('Aguardando a TV…'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(button()).onPressed, isNull);

    socket.emit(shotEvent('outra', at));
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.text('Aguardando a TV…'), findsOneWidget);

    socket.emit(shotEvent('a', at));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();
    await tester.pump();
    expect(find.text('Aguardando a TV…'), findsNothing);
    expect(
      imageUrl(tester),
      'http://localhost:8080/api/v1/devices/a/screenshot'
      '?t=${at.millisecondsSinceEpoch}',
    );
    expect(find.text('Capturada há 2 min'), findsOneWidget);
    expect(
      find.text('A captura fica só na memória do servidor.'),
      findsOneWidget,
    );
    expect(tester.widget<OutlinedButton>(button()).onPressed, isNotNull);

    await tester.pump(screenshotWait);
    expect(find.text('A TV não respondeu.'), findsNothing);
  });

  testWidgets('sem evento em 15 s a TV não respondeu', (tester) async {
    await open(tester);
    await tester.tap(button());
    await tester.pump();

    await tester.pump(screenshotWait - const Duration(seconds: 1));
    expect(find.text('Aguardando a TV…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('A TV não respondeu.'), findsOneWidget);
    expect(find.text('Aguardando a TV…'), findsNothing);
    expect(tester.widget<OutlinedButton>(button()).onPressed, isNotNull);
  });

  testWidgets('409 e 429 viram mensagens', (tester) async {
    await open(tester);
    api.screenshotError = const ApiException(
      'A TV está offline.',
      code: 'device_offline',
      status: 409,
    );
    await tester.tap(button());
    await tester.pump();
    expect(find.text('A TV está offline.'), findsOneWidget);
    expect(find.text('Aguardando a TV…'), findsNothing);

    api.screenshotError = const ApiException(
      'Aguarde alguns segundos para capturar de novo.',
      code: 'too_many_requests',
      status: 429,
    );
    await tester.tap(button());
    await tester.pump();
    expect(
      find.text('Aguarde alguns segundos para capturar de novo.'),
      findsOneWidget,
    );
  });

  testWidgets('offline desabilita o botão', (tester) async {
    await open(tester, online: false);
    expect(tester.widget<OutlinedButton>(button()).onPressed, isNull);
  });

  testWidgets('mostra a última captura existente ao abrir', (tester) async {
    api.screenshotAt['a'] = at;
    await open(tester);
    expect(imageUrl(tester), contains('t=${at.millisecondsSinceEpoch}'));
    expect(find.text('Capturada há 2 min'), findsOneWidget);
  });
}
