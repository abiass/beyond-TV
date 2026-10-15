import 'package:beyond_dashboard/src/api/groups.dart';
import 'package:beyond_dashboard/src/api/playlists.dart';
import 'package:beyond_dashboard/src/api/schedules.dart';
import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';

DeviceSummary tv(String id, String name, {bool online = false, int? groupId}) =>
    DeviceSummary(
      id: id,
      name: name,
      online: online,
      createdAt: DateTime.utc(2026, 10, 1),
      groupId: groupId,
    );

void main() {
  late FakeApi api;

  setUp(() {
    api = FakeApi(adminPassword: 'senha-forte-1', loggedIn: true)
      ..devices.addAll([
        tv('a', 'Balcão', online: true, groupId: 3),
        tv('b', 'Vitrine'),
        tv('c', 'Estoque', groupId: 4),
      ])
      ..groups.addAll([
        Group(
          id: 3,
          name: 'Recepção',
          deviceIds: ['a'],
          createdAt: DateTime.utc(2026, 10, 1),
        ),
        Group(
          id: 4,
          name: 'Loja',
          deviceIds: ['c'],
          createdAt: DateTime.utc(2026, 10, 1),
        ),
      ])
      ..playlists.add(
        Playlist(id: 'p1', name: 'Manhã', createdAt: DateTime.utc(2026, 10, 1)),
      );
  });

  Future<void> openDetail(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(dashboardWith(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Grupos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recepção'));
    await tester.pumpAndSettle();
  }

  testWidgets('mostra as TVs com marcação dos membros', (tester) async {
    await openDetail(tester);

    CheckboxListTile tile(String name) => tester.widget(
          find.widgetWithText(CheckboxListTile, name),
        );
    expect(tile('Balcão').value, isTrue);
    expect(tile('Vitrine').value, isFalse);
    expect(tile('Estoque').value, isFalse);
    expect(find.text('Online'), findsOneWidget);
  });

  testWidgets('salvar membros envia a lista marcada', (tester) async {
    await openDetail(tester);

    await tester.tap(find.text('Vitrine'));
    await tester.tap(find.text('Estoque'));
    await tester.tap(find.text('Balcão'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar membros'));
    await tester.pumpAndSettle();

    expect(api.memberCalls.single.$1, 3);
    expect(api.memberCalls.single.$2, ['b', 'c']);
    expect(find.text('Membros salvos.'), findsOneWidget);
    expect(api.devices.firstWhere((d) => d.id == 'a').groupId, isNull);
  });

  testWidgets('escolher playlist define o conteúdo padrão do grupo',
      (tester) async {
    await openDetail(tester);
    expect(find.text('Nada atribuído.'), findsOneWidget);

    await tester.tap(find.byType(DropdownMenu<PlaylistSummary>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manhã').last);
    await tester.pumpAndSettle();

    expect(api.groupContentCalls.single.$1, 3);
    expect(api.groupContentCalls.single.$2, {'playlistId': 'p1'});
    expect(find.text('Atribuído: Playlist: Manhã'), findsOneWidget);
  });

  testWidgets('site validado, enviado e depois removido', (tester) async {
    await openDetail(tester);
    final url = find.widgetWithText(TextFormField, 'Endereço do site');

    await tester.enterText(url, 'ftp://example.local');
    await tester.tap(find.text('Exibir neste grupo'));
    await tester.pumpAndSettle();
    expect(api.groupContentCalls, isEmpty);

    await tester.enterText(url, 'https://example.local/promo');
    await tester.tap(find.text('Exibir neste grupo'));
    await tester.pumpAndSettle();
    expect(api.groupContentCalls.single.$2, {
      'url': 'https://example.local/promo',
    });
    expect(find.text('Conteúdo do grupo salvo.'), findsOneWidget);

    await tester.tap(find.text('Parar de exibir'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Parar'));
    await tester.pumpAndSettle();

    expect(api.groupContentCalls.last.$2, isEmpty);
    expect(find.text('Nada atribuído.'), findsOneWidget);
  });

  testWidgets('lista os agendamentos do grupo e abre a agenda', (tester) async {
    api.schedules.add(
      Schedule(
        id: 's1',
        name: 'Almoço',
        playlistId: 'p1',
        groupId: 3,
        days: {1, 2, 3, 4, 5},
        startMinute: 660,
        endMinute: 840,
        priority: 10,
        createdAt: DateTime.utc(2026, 10, 1),
      ),
    );
    await openDetail(tester);

    expect(find.text('Almoço'), findsOneWidget);
    expect(
      find.text('Seg a Sex · 11:00-14:00 · prioridade 10'),
      findsOneWidget,
    );

    await tester.tap(find.text('Abrir agenda'));
    await tester.pumpAndSettle();
    expect(find.text('Agenda'), findsOneWidget);
    expect(find.text('Grupo: Recepção'), findsWidgets);
  });
}
