import 'dart:convert';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_tv/src/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fake_socket.dart';
import '../support/fakes.dart';

void main() {
  late List<PairRequest> requests;
  late MemoryCredentialStore store;

  http.Response Function(http.Request) pairWith(http.Response response) =>
      (request) {
        requests.add(
          PairRequest.fromJson(
            jsonDecode(request.body) as Map<String, Object?>,
          ),
        );
        return response;
      };

  final paired = http.Response(
    jsonEncode(
      const PairResponse(
        deviceId: 'tv1',
        deviceToken: 'token',
        serverId: 'abc',
      ).toJson(),
    ),
    201,
  );

  setUp(() {
    requests = [];
    store = MemoryCredentialStore();
  });

  /// Abre o app já na tela de pareamento do PC-SALA.
  Future<void> openPairing(
    WidgetTester tester, {
    http.Response? response,
    Set<String> onlineHosts = const {'192.168.0.10'},
  }) async {
    useTvScreen(tester);
    await tester.pumpWidget(
      TvApp(
        mediaRoot: fakeMediaRoot,
        credentials: store,
        discovery: FakeDiscovery([pcSala]),
        deviceInfo: const FakeDeviceInfo(),
        connector: FakeConnector().call,
        api: fakeApi(
          onlineHosts: onlineHosts,
          routes: {'POST /api/v1/pair': pairWith(response ?? paired)},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('PC-SALA'));
    await tester.pumpAndSettle();
  }

  Future<void> typeOnKeyboard(WidgetTester tester, String text) async {
    for (final char in text.split('')) {
      await tester.sendKeyEvent(
        LogicalKeyboardKey.findKeyByKeyId(char.toLowerCase().codeUnitAt(0))!,
        character: char.toLowerCase(),
      );
    }
    await tester.pumpAndSettle();
  }

  String slots(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.bySemanticsLabel(RegExp('^Código digitado')),
          matching: find.byType(Text),
        ),
      )
      .map((text) => text.data)
      .join();

  testWidgets('cabe numa TV 1080p sem estourar o layout', (tester) async {
    await openPairing(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Parear esta TV'), findsOneWidget);
  });

  testWidgets('digita com o D-pad: setas andam e OK aperta a tecla', (
    tester,
  ) async {
    await openPairing(tester);

    // O foco começa na primeira tecla ("2").
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    // Grade de 6 colunas: à direita do "2" fica o "3"; abaixo do "3", o "9".
    expect(slots(tester), '39');
  });

  testWidgets('envia sozinho ao completar o código e mostra "pareada"', (
    tester,
  ) async {
    await openPairing(tester);

    await typeOnKeyboard(tester, 'k7m4qx');

    expect(requests.single.code, 'K7M4QX');
    expect(requests.single.deviceInfo.model, 'X1');
    expect(find.text('TV pareada!'), findsOneWidget);

    final saved = store.saved!;
    expect(saved.deviceId, 'tv1');
    expect(saved.deviceToken, 'token');
    expect(saved.server.serverId, 'abc');
    expect(saved.server.hostPort, '192.168.0.10:8787');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ignora teclas fora do alfabeto e apaga com Backspace', (
    tester,
  ) async {
    await openPairing(tester);

    await typeOnKeyboard(tester, 'k0o1');
    expect(slots(tester), 'K');

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(slots(tester), '');
  });

  testWidgets('código expirado mostra o motivo e limpa o código', (
    tester,
  ) async {
    await openPairing(
      tester,
      response: apiError(400, 'expired_code', 'Código expirado.'),
    );

    await typeOnKeyboard(tester, 'k7m4qx');

    expect(find.text('Código expirado.'), findsOneWidget);
    expect(slots(tester), '');
    expect(store.saved, isNull);
    expect(find.text('Parear esta TV'), findsOneWidget);
  });

  testWidgets('servidor inacessível mantém o código para tentar de novo', (
    tester,
  ) async {
    await openPairing(tester, onlineHosts: {});

    await typeOnKeyboard(tester, 'k7m4qx');

    expect(find.textContaining('Servidor inacessível'), findsOneWidget);
    expect(slots(tester), 'K7M4QX');
  });

  testWidgets('"Trocar servidor" volta para a lista', (tester) async {
    await openPairing(tester);

    await tester.tap(find.text('Trocar servidor'));
    await tester.pumpAndSettle();

    expect(find.text('Escolha o servidor'), findsOneWidget);
  });
}
