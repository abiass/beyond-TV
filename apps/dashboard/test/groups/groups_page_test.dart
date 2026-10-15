import 'package:beyond_dashboard/src/api/groups.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';

Group group(int id, String name, {List<String> deviceIds = const []}) => Group(
      id: id,
      name: name,
      deviceIds: deviceIds,
      createdAt: DateTime.utc(2026, 10, 1),
    );

void main() {
  late FakeApi api;

  setUp(() {
    api = FakeApi(adminPassword: 'senha-forte-1', loggedIn: true)
      ..groups.addAll([
        group(3, 'Recepção', deviceIds: ['a', 'b']),
        group(4, 'Loja'),
      ]);
  });

  Future<void> openGroups(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(dashboardWith(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Grupos'));
    await tester.pumpAndSettle();
  }

  Finder nameField() => find.widgetWithText(TextFormField, 'Nome');

  testWidgets('lista nome, quantidade de TVs e conteúdo padrão',
      (tester) async {
    await openGroups(tester);

    expect(find.text('Recepção'), findsOneWidget);
    expect(find.text('2 TVs · Sem conteúdo padrão'), findsOneWidget);
    expect(find.text('0 TVs · Sem conteúdo padrão'), findsOneWidget);
  });

  testWidgets('criar abre o detalhe do novo grupo', (tester) async {
    await openGroups(tester);

    await tester.tap(find.text('Novo grupo'));
    await tester.pumpAndSettle();
    await tester.enterText(nameField(), ' Cozinha ');
    await tester.tap(find.text('Criar'));
    await tester.pumpAndSettle();

    expect(api.groups.map((g) => g.name), ['Recepção', 'Loja', 'Cozinha']);
    expect(find.text('TVs do grupo'), findsOneWidget);
  });

  testWidgets('nome repetido (409) mostra a mensagem e mantém o diálogo',
      (tester) async {
    await openGroups(tester);

    await tester.tap(find.text('Novo grupo'));
    await tester.pumpAndSettle();
    await tester.enterText(nameField(), 'loja');
    await tester.tap(find.text('Criar'));
    await tester.pumpAndSettle();

    expect(find.text('Esse nome já está em uso.'), findsOneWidget);
    expect(api.groups, hasLength(2));
  });

  testWidgets('renomeia', (tester) async {
    await openGroups(tester);

    await tester.tap(find.byTooltip('Ações').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Renomear'));
    await tester.pumpAndSettle();
    await tester.enterText(nameField(), 'Hall');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(api.groups.map((g) => g.name), contains('Hall'));
    expect(find.text('Hall'), findsOneWidget);
  });

  testWidgets('apagar pede confirmação e avisa o efeito', (tester) async {
    await openGroups(tester);

    await tester.tap(find.byTooltip('Ações').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apagar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('As TVs ficam sem grupo'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(api.groups, hasLength(2));

    await tester.tap(find.byTooltip('Ações').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apagar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apagar'));
    await tester.pumpAndSettle();

    expect(api.groups.map((g) => g.name), ['Recepção']);
    expect(find.text('Loja'), findsNothing);
  });
}
