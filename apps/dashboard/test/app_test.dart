import 'package:beyond_dashboard/src/api/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

void main() {
  Finder field(String label) => find.widgetWithText(TextFormField, label);

  testWidgets('servidor novo abre a configuração inicial', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(dashboardWith(api));
    await tester.pumpAndSettle();

    expect(find.text('Bem-vindo ao Beyond TV'), findsOneWidget);

    await tester.enterText(field('Senha'), 'senha-forte-1');
    await tester.enterText(field('Repita a senha'), 'senha-forte-1');
    await tester.tap(find.text('Criar administrador'));
    await tester.pumpAndSettle();

    expect(api.adminPassword, 'senha-forte-1');
    expect(find.text('Nenhuma TV pareada ainda.'), findsOneWidget);
    expect(find.text('admin'), findsOneWidget);
  });

  testWidgets('setup valida a senha antes de enviar', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(dashboardWith(api));
    await tester.pumpAndSettle();

    await tester.enterText(field('Senha'), 'curta');
    await tester.enterText(field('Repita a senha'), 'outra');
    await tester.tap(find.text('Criar administrador'));
    await tester.pumpAndSettle();

    expect(
      find.text('A senha deve ter pelo menos 8 caracteres.'),
      findsOneWidget,
    );
    expect(find.text('As senhas não conferem.'), findsOneWidget);
    expect(api.adminPassword, isNull);
  });

  testWidgets('sem sessão pede login e mostra erro de senha', (tester) async {
    final api = FakeApi(adminPassword: 'senha-forte-1');
    await tester.pumpWidget(dashboardWith(api));
    await tester.pumpAndSettle();

    await tester.enterText(field('Usuário'), 'admin');
    await tester.enterText(field('Senha'), 'errada!!');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('Usuário ou senha incorretos.'), findsOneWidget);
    expect(api.loggedIn, isFalse);

    await tester.enterText(field('Senha'), 'senha-forte-1');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('Nenhuma TV pareada ainda.'), findsOneWidget);
  });

  testWidgets('com sessão abre o painel e sair volta ao login', (tester) async {
    final api = FakeApi(adminPassword: 'senha-forte-1', loggedIn: true);
    await tester.pumpWidget(dashboardWith(api));
    await tester.pumpAndSettle();

    expect(find.text('Nenhuma TV pareada ainda.'), findsOneWidget);

    await tester.tap(find.byTooltip('Sair'));
    await tester.pumpAndSettle();

    expect(api.loggedIn, isFalse);
    expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
  });

  testWidgets('servidor fora do ar mostra o erro e permite tentar de novo',
      (tester) async {
    final api = FakeApi(adminPassword: 'senha-forte-1')
      ..failure = const ApiException('Servidor fora do ar.');
    await tester.pumpWidget(dashboardWith(api));
    await tester.pumpAndSettle();

    expect(find.text('Servidor fora do ar.'), findsOneWidget);

    api.failure = null;
    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
  });
}
