import 'package:beyond_dashboard/src/api/playlists.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';

void main() {
  late FakeApi api;

  setUp(() {
    api = FakeApi(adminPassword: 'senha-forte-1', loggedIn: true)
      ..playlists.addAll([
        Playlist(
          id: 'p1',
          name: 'Recepção',
          createdAt: DateTime.utc(2026, 10, 1),
        ),
      ]);
  });

  Future<void> openPlaylists(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(dashboardWith(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Playlists'));
    await tester.pumpAndSettle();
  }

  testWidgets('lista nome e quantidade de itens', (tester) async {
    await openPlaylists(tester);

    expect(find.text('Recepção'), findsOneWidget);
    expect(find.text('0 itens'), findsOneWidget);
  });

  testWidgets('criar abre o editor da nova playlist', (tester) async {
    await openPlaylists(tester);

    await tester.tap(find.text('Nova playlist'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome'),
      ' Loja ',
    );
    await tester.tap(find.text('Criar'));
    await tester.pumpAndSettle();

    expect(api.playlists.map((p) => p.name), ['Recepção', 'Loja']);
    expect(find.text('Playlist vazia. Adicione mídias.'), findsOneWidget);
  });

  testWidgets('nome vazio é recusado sem chamar a API', (tester) async {
    await openPlaylists(tester);

    await tester.tap(find.text('Nova playlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Criar'));
    await tester.pumpAndSettle();

    expect(find.text('O nome deve ter de 1 a 64 caracteres.'), findsOneWidget);
    expect(api.playlists, hasLength(1));
  });

  testWidgets('renomeia', (tester) async {
    await openPlaylists(tester);

    await tester.tap(find.byTooltip('Ações'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Renomear'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Nome'), 'Hall');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(api.playlists.single.name, 'Hall');
    expect(find.text('Hall'), findsOneWidget);
  });

  testWidgets('apagar pede confirmação', (tester) async {
    await openPlaylists(tester);

    await tester.tap(find.byTooltip('Ações'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apagar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(api.playlists, hasLength(1));

    await tester.tap(find.byTooltip('Ações'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apagar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apagar'));
    await tester.pumpAndSettle();

    expect(api.playlists, isEmpty);
    expect(find.text('Nenhuma playlist ainda.'), findsOneWidget);
  });
}
