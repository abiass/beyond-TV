import 'package:beyond_dashboard/src/api/api_client.dart';
import 'package:beyond_dashboard/src/api/groups.dart';
import 'package:beyond_dashboard/src/api/playlists.dart';
import 'package:beyond_dashboard/src/api/schedules.dart';
import 'package:beyond_dashboard/src/schedules/schedules_controller.dart';
import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';

Schedule lunch() => Schedule(
      id: 's1',
      name: 'Almoço',
      playlistId: 'p1',
      groupId: 3,
      days: {1, 2},
      startMinute: 660,
      endMinute: 840,
      priority: 10,
      createdAt: DateTime.utc(2026, 10, 1),
    );

Schedule night() => Schedule(
      id: 's2',
      name: 'Madrugada',
      playlistId: 'p1',
      groupId: 3,
      days: {7},
      startMinute: 22 * 60,
      endMinute: 2 * 60,
      priority: 5,
      createdAt: DateTime.utc(2026, 10, 2),
    );

void main() {
  late FakeApi api;

  setUp(() {
    api = FakeApi(adminPassword: 'senha-forte-1', loggedIn: true)
      ..devices.add(
        DeviceSummary(
          id: 'a',
          name: 'Balcão',
          online: true,
          createdAt: DateTime.utc(2026, 10, 1),
          groupId: 3,
        ),
      )
      ..groups.add(
        Group(
          id: 3,
          name: 'Recepção',
          deviceIds: ['a'],
          createdAt: DateTime.utc(2026, 10, 1),
        ),
      )
      ..playlists.add(
        Playlist(id: 'p1', name: 'Manhã', createdAt: DateTime.utc(2026, 10, 1)),
      )
      ..schedules.addAll([lunch(), night()]);
  });

  Future<void> openAgenda(WidgetTester tester, {bool pick = true}) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(dashboardWith(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Agenda'));
    await tester.pumpAndSettle();
    if (!pick) return;
    await tester.tap(find.byType(DropdownMenu<ScheduleTarget>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grupo: Recepção').last);
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> openNewDialog(WidgetTester tester) async {
    await tester.tap(find.text('Novo agendamento'));
    await tester.pumpAndSettle();
  }

  Future<void> choosePlaylist(WidgetTester tester) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manhã').last);
    await tester.pumpAndSettle();
  }

  testWidgets('sem alvo pede para escolher', (tester) async {
    await openAgenda(tester, pick: false);

    expect(find.text('Escolha uma TV ou um grupo.'), findsOneWidget);
    expect(find.text('Novo agendamento'), findsNothing);
  });

  testWidgets('a grade mostra os blocos, inclusive a virada de noite',
      (tester) async {
    await openAgenda(tester);

    expect(find.byKey(const ValueKey('block-s1-1-660')), findsOneWidget);
    expect(find.byKey(const ValueKey('block-s1-2-660')), findsOneWidget);
    // Domingo 22:00 até segunda 02:00.
    expect(find.byKey(const ValueKey('block-s2-7-1320')), findsOneWidget);
    expect(find.byKey(const ValueKey('block-s2-1-0')), findsOneWidget);
    expect(find.text('Seg'), findsOneWidget);
    expect(find.text('Dom'), findsOneWidget);
  });

  testWidgets('a lista segue a precedência (prioridade maior primeiro)',
      (tester) async {
    await openAgenda(tester);

    final almoco = tester.getTopLeft(find.byType(Card).first);
    expect(
      find.descendant(
        of: find.byType(Card).first,
        matching: find.text('Almoço'),
      ),
      findsOneWidget,
    );
    expect(almoco.dy, lessThan(tester.getTopLeft(find.byType(Card).last).dy));
    expect(
      find.textContaining('Seg, Ter · 11:00-14:00 · prioridade 10'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Dom · 22:00-02:00 (+1) · prioridade 5'),
      findsOneWidget,
    );
  });

  testWidgets('abre direto no alvo vindo do detalhe da TV', (tester) async {
    api.schedules.add(
      Schedule(
        id: 's3',
        name: 'Só do balcão',
        playlistId: 'p1',
        deviceId: 'a',
        days: {3},
        startMinute: 600,
        endMinute: 660,
        priority: 1,
        createdAt: DateTime.utc(2026, 10, 3),
      ),
    );
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(dashboardWith(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Balcão'));
    await tester.pumpAndSettle();
    expect(find.text('Almoço (Grupo)'), findsOneWidget);
    expect(find.text('Só do balcão (TV)'), findsOneWidget);

    await tester.tap(find.text('Abrir agenda'));
    await tester.pumpAndSettle();

    expect(find.text('TV: Balcão'), findsWidgets);
    expect(find.text('Só do balcão'), findsWidgets);
    expect(find.text('Almoço'), findsNothing);
  });

  testWidgets('criar envia dias, HH:MM e prioridade', (tester) async {
    await openAgenda(tester);
    await openNewDialog(tester);

    await tester.enterText(field('Nome'), ' Noite ');
    await choosePlaylist(tester);
    await tester.tap(find.text('Dias úteis'));
    await tester.enterText(field('Início'), '22:00');
    await tester.enterText(field('Fim'), '06:30');
    await tester.enterText(field('Prioridade (0 a 100)'), '20');
    await tester.pumpAndSettle();
    expect(find.text('Termina no dia seguinte.'), findsOneWidget);

    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(api.scheduleCreated.single, {
      'name': 'Noite',
      'playlistId': 'p1',
      'groupId': 3,
      'days': [1, 2, 3, 4, 5],
      'start': '22:00',
      'end': '06:30',
      'priority': 20,
    });
    expect(find.text('Noite'), findsWidgets);
  });

  testWidgets('avisa quando a faixa cobre 24 horas', (tester) async {
    await openAgenda(tester);
    await openNewDialog(tester);

    await tester.enterText(field('Início'), '08:00');
    await tester.enterText(field('Fim'), '08:00');
    await tester.pumpAndSettle();

    expect(find.text('Cobre 24 horas.'), findsOneWidget);
  });

  testWidgets('sem dia, horário inválido ou prioridade fora: não chama a API',
      (tester) async {
    await openAgenda(tester);
    await openNewDialog(tester);

    await tester.enterText(field('Nome'), 'X');
    await choosePlaylist(tester);
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Escolha ao menos um dia.'), findsOneWidget);

    await tester.tap(find.text('Todos'));
    await tester.enterText(field('Início'), '25:00');
    await tester.enterText(field('Fim'), '8h');
    await tester.enterText(field('Prioridade (0 a 100)'), '101');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Use HH:MM, de 00:00 a 23:59.'), findsNWidgets(2));
    expect(find.text('Use um número de 0 a 100.'), findsOneWidget);
    expect(find.text('Escolha ao menos um dia.'), findsNothing);
    expect(api.scheduleCreated, isEmpty);
  });

  testWidgets('erro do servidor aparece no diálogo', (tester) async {
    await openAgenda(tester);
    await openNewDialog(tester);
    await tester.enterText(field('Nome'), 'X');
    await choosePlaylist(tester);
    await tester.tap(find.text('Todos'));
    api.failure = const ApiException(
      'A playlist não existe mais.',
      code: 'unknown_playlist',
      status: 400,
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('A playlist não existe mais.'), findsOneWidget);
    expect(find.text('Novo agendamento'), findsWidgets);
  });

  testWidgets('editar manda o agendamento alterado', (tester) async {
    await openAgenda(tester);

    await tester.tap(find.byTooltip('Editar').first);
    await tester.pumpAndSettle();
    expect(field('Nome'), findsOneWidget);
    await tester.enterText(field('Nome'), 'Almoço longo');
    await tester.enterText(field('Fim'), '15:00');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    final (id, body) = api.scheduleUpdated.single;
    expect(id, 's1');
    expect(body['name'], 'Almoço longo');
    expect(body['end'], '15:00');
    expect(body['days'], [1, 2]);
    expect(
      find.textContaining('Seg, Ter · 11:00-15:00 · prioridade 10'),
      findsOneWidget,
    );
  });

  testWidgets('apagar pede confirmação', (tester) async {
    await openAgenda(tester);

    await tester.tap(find.byTooltip('Apagar').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(api.scheduleDeleted, isEmpty);

    await tester.tap(find.byTooltip('Apagar').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apagar'));
    await tester.pumpAndSettle();

    expect(api.scheduleDeleted, ['s1']);
    expect(find.byKey(const ValueKey('block-s1-1-660')), findsNothing);
  });
}
