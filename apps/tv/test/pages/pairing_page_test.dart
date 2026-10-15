import 'dart:convert';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_tv/src/app.dart';
import 'package:beyond_tv/src/widgets/tv_button.dart';
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
    // Abre a aprovação no painel; sem a rota (404) ela cai sozinha no
    // código digitado. Servidor fora do ar: escolhe "Digitar código".
    // (Sem pumpAndSettle: o indicador de espera gira sem parar.)
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    if (find.textContaining('digite aqui o código').evaluate().isEmpty) {
      await tester.tap(find.text('Digitar código'));
    }
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

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, [
    int n = 1,
  ]) async {
    for (var i = 0; i < n; i++) {
      await tester.sendKeyEvent(key);
    }
    await tester.pumpAndSettle();
  }

  testWidgets('o D-pad não sai do teclado por cima nem por baixo', (
    tester,
  ) async {
    await openPairing(tester);

    // Descer além da última fileira e subir além da primeira não tira o
    // foco do teclado (antes ele ia para "Trocar servidor" e se perdia).
    await press(tester, LogicalKeyboardKey.arrowDown, 8);
    await press(tester, LogicalKeyboardKey.select);
    await press(tester, LogicalKeyboardKey.arrowUp, 8);
    await press(tester, LogicalKeyboardKey.select);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowDown, 8);
    await press(tester, LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.select);

    // Coluna 1: para no "Z" e volta ao "2". Coluna 2: para no Apagar e,
    // uma acima, aperta o "U".
    expect(slots(tester), 'Z2U');
  });

  testWidgets('última fileira incompleta: descer leva à tecla mais próxima', (
    tester,
  ) async {
    await openPairing(tester);

    // Coluna 6 ("7", "D", "K", "S", "Y"): abaixo do "Y" não há tecla; o
    // foco vai para o OK, que envia e reclama do código incompleto.
    await press(tester, LogicalKeyboardKey.arrowRight, 5);
    await press(tester, LogicalKeyboardKey.arrowDown, 4);
    await press(tester, LogicalKeyboardKey.select);
    expect(slots(tester), 'Y');

    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.select);
    expect(find.text('Digite os 6 caracteres.'), findsOneWidget);
  });

  testWidgets('à esquerda vai para "Trocar servidor" e à direita volta', (
    tester,
  ) async {
    await openPairing(tester);

    await press(tester, LogicalKeyboardKey.arrowDown, 5); // "Z"
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<TvButton>()
          ?.label,
      'Trocar servidor',
    );

    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.select);
    expect(slots(tester).length, 1);
  });

  testWidgets('depois de um código errado o foco volta ao teclado', (
    tester,
  ) async {
    await openPairing(
      tester,
      response: apiError(400, 'invalid_code', 'Código inválido.'),
    );

    // Digita "222222" pelo D-pad: o envio desabilita as teclas.
    await press(tester, LogicalKeyboardKey.select, 6);
    expect(find.text('Código inválido.'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.select);
    expect(slots(tester), '3');
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
