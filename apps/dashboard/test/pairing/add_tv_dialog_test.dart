import 'package:beyond_dashboard/src/api/api_client.dart';
import 'package:beyond_dashboard/src/pairing/add_tv_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi(adminPassword: 'senha-forte-1', loggedIn: true));

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(dashboardWith(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar TV'));
    // O diálogo tem timers periódicos: avança o tempo em vez de esperar
    // assentar.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('mostra o código com contagem regressiva', (tester) async {
    await openDialog(tester);

    expect(find.text('K7M 4Q2'), findsOneWidget);
    expect(find.text('Expira em 10:00'), findsOneWidget);
    expect(find.text('Aguardando a TV…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 61));
    expect(find.text('Expira em 8:59'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pump();
  });

  testWidgets('avisa quando a TV pareia', (tester) async {
    await openDialog(tester);

    api.status = const PairingStatus(
      PairingState.paired,
      deviceName: 'Acme TV 4K',
    );
    await tester.pump(AddTvDialog.pollInterval);
    await tester.pump();

    expect(find.text('TV pareada!'), findsOneWidget);
    expect(find.text('"Acme TV 4K" já aparece no painel.'), findsOneWidget);

    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    expect(find.byType(AddTvDialog), findsNothing);
  });

  testWidgets('código vencido permite gerar outro', (tester) async {
    await openDialog(tester);

    await tester.pump(const Duration(minutes: 10, seconds: 1));

    expect(find.text('Código expirado'), findsOneWidget);
    final calls = api.statusCalls;
    await tester.pump(const Duration(seconds: 10));
    expect(api.statusCalls, calls, reason: 'para de consultar ao expirar');

    await tester.tap(find.text('Gerar novo código'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.codes, hasLength(2));
    expect(find.text('K7M 4Q3'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pump();
  });

  testWidgets('sessão expirada fecha o diálogo e volta ao login', (
    tester,
  ) async {
    await openDialog(tester);

    api
      ..loggedIn = false
      ..failure = const ApiException(
        'Faça login para continuar.',
        code: 'unauthorized',
        status: 401,
      );
    await tester.pump(AddTvDialog.pollInterval);
    await tester.pumpAndSettle();

    expect(find.byType(AddTvDialog), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
  });
}
