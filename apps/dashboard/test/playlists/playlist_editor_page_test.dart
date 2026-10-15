import 'package:beyond_dashboard/src/api/api_client.dart';
import 'package:beyond_dashboard/src/api/playlists.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/library.dart';

void main() {
  late FakeApi api;

  setUp(() {
    final media = sampleMedia();
    api = FakeApi(adminPassword: 'senha-forte-1', loggedIn: true)
      ..media.addAll(media)
      ..playlists.add(
        Playlist(
          id: 'p1',
          name: 'Recepção',
          createdAt: DateTime.utc(2026, 10, 1),
          items: [
            PlaylistEntry(media: media[0], durationSeconds: 15),
            PlaylistEntry(media: media[1]),
          ],
        ),
      );
  });

  Future<void> openEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(dashboardWith(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Playlists'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recepção'));
    await tester.pumpAndSettle();
  }

  Finder duration(int index) => find.byType(TextField).at(index);
  Finder saveButton() => find.widgetWithText(FilledButton, 'Salvar');
  bool canSave(WidgetTester tester) =>
      tester.widget<FilledButton>(saveButton()).onPressed != null;

  testWidgets('carrega os itens com as durações', (tester) async {
    await openEditor(tester);

    expect(find.text('Promoção'), findsOneWidget);
    expect(find.text('Institucional'), findsOneWidget);
    expect(tester.widget<TextField>(duration(0)).controller!.text, '15');
    expect(tester.widget<TextField>(duration(1)).controller!.text, '');
    expect(find.text('até o fim'), findsOneWidget);
    expect(find.textContaining('de 5 a 86400 segundos'), findsOneWidget);
    expect(canSave(tester), isFalse);
  });

  testWidgets('reordenar e salvar manda a lista na nova ordem', (tester) async {
    await openEditor(tester);

    // O arrastar em si é do Flutter; aqui chamamos o callback da lista.
    tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .onReorderItem!(0, 1);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Alterações não salvas'), findsOneWidget);

    await tester.tap(saveButton());
    await tester.pumpAndSettle();

    expect(api.savedItems.single.$1, 'p1');
    expect(api.savedItems.single.$2, [('vid', null), ('img', 15)]);
    expect(find.text('Playlist salva.'), findsOneWidget);
    expect(find.text('Alterações não salvas'), findsNothing);
  });

  testWidgets('remove item e salva', (tester) async {
    await openEditor(tester);

    await tester.tap(find.byTooltip('Remover da playlist').first);
    await tester.pumpAndSettle();
    await tester.tap(saveButton());
    await tester.pumpAndSettle();

    expect(api.savedItems.single.$2, [('vid', null)]);
  });

  testWidgets('adiciona várias mídias da biblioteca', (tester) async {
    await openEditor(tester);

    await tester.tap(find.text('Adicionar mídia'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Painel'));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Promoção'));
    await tester.pump();
    await tester.tap(find.text('Adicionar (2)'));
    await tester.pumpAndSettle();

    expect(find.text('4 de 200 itens'), findsOneWidget);
    await tester.tap(saveButton());
    await tester.pumpAndSettle();

    expect(api.savedItems.single.$2, [
      ('img', 15),
      ('vid', null),
      ('site', null),
      ('img', null),
    ]);
  });

  testWidgets('duração fora de 5 a 86400 bloqueia o salvar', (tester) async {
    await openEditor(tester);

    for (final invalid in ['4', '86401']) {
      await tester.enterText(duration(0), invalid);
      await tester.pump();
      expect(find.text('Use de 5 a 86400 s.'), findsOneWidget);
      expect(canSave(tester), isFalse);
    }

    for (final valid in ['5', '86400']) {
      await tester.enterText(duration(0), valid);
      await tester.pump();
      expect(find.text('Use de 5 a 86400 s.'), findsNothing);
      expect(canSave(tester), isTrue);
    }

    await tester.enterText(duration(0), '');
    await tester.pump();
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(api.savedItems.single.$2.first, ('img', null));
  });

  testWidgets('sair com alterações pendentes pede confirmação', (tester) async {
    await openEditor(tester);
    await tester.enterText(duration(0), '30');
    await tester.pump();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Sair sem salvar?'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Promoção'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sair'));
    await tester.pumpAndSettle();
    expect(find.text('Nova playlist'), findsOneWidget);
  });

  testWidgets('erro do servidor aparece na tela', (tester) async {
    await openEditor(tester);
    await tester.enterText(duration(0), '30');
    await tester.pump();
    api.failure = const ApiException(
      'Duração inválida.',
      code: 'invalid_duration',
      status: 400,
    );
    await tester.tap(saveButton());
    await tester.pumpAndSettle();

    expect(find.text('Duração inválida.'), findsOneWidget);
  });
}
