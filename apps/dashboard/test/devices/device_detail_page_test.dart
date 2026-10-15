import 'package:beyond_dashboard/src/api/playlists.dart';
import 'package:beyond_dashboard/src/api/media.dart';
import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_admin_socket.dart';
import '../support/fake_api.dart';
import '../support/library.dart';

DeviceSummary tv(String id, String name, {bool online = false}) =>
    DeviceSummary(
      id: id,
      name: name,
      online: online,
      createdAt: DateTime.utc(2026, 10, 1),
      info: const DeviceInfo(
        appVersion: '0.5.0',
        manufacturer: 'Acme',
        model: 'TV 4K',
        androidVersion: '11',
        screenWidth: 1920,
        screenHeight: 1080,
      ),
      lastSeenAt: DateTime.now().subtract(const Duration(minutes: 5)),
      currentItem: online ? 'https://example.local/painel' : null,
    );

void main() {
  late FakeApi api;
  late FakeAdminSocket socket;

  setUp(() {
    api = FakeApi(adminPassword: 'senha-forte-1', loggedIn: true)
      ..devices.addAll([
        tv('a', 'Zeta'),
        tv('b', 'Recepção', online: true),
      ]);
    socket = FakeAdminSocket();
  });

  Future<void> openDetail(WidgetTester tester, String name) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(dashboardWith(api, socket: socket));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  testWidgets('tocar no card abre os detalhes', (tester) async {
    await openDetail(tester, 'Recepção');

    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Recepção'), findsWidgets);
    expect(find.textContaining('Online'), findsOneWidget);
    expect(find.text('Acme TV 4K'), findsOneWidget);
    expect(find.text('Android 11'), findsOneWidget);
    expect(find.text('App 0.5.0'), findsOneWidget);
    expect(find.text('1920 x 1080'), findsOneWidget);
    expect(find.text('Exibindo agora'), findsOneWidget);
  });

  testWidgets('URL inválida mostra a mensagem e não chama a API',
      (tester) async {
    await openDetail(tester, 'Recepção');

    await tester.enterText(field('Endereço do site'), 'javascript:alert(1)');
    await tester.tap(find.text('Exibir nesta TV'));
    await tester.pumpAndSettle();

    expect(
      find.text('Use um link que comece com http:// ou https://.'),
      findsOneWidget,
    );
    expect(api.setUrlCalls, 0);
  });

  testWidgets('URL válida envia, avisa e aparece no card da lista',
      (tester) async {
    await openDetail(tester, 'Recepção');

    await tester.enterText(
      field('Endereço do site'),
      'https://example.local/vendas',
    );
    await tester.enterText(field('Nome (opcional)'), 'Vendas');
    await tester.tap(find.text('Exibir nesta TV'));
    await tester.pumpAndSettle();

    expect(find.text('Conteúdo enviado para a TV.'), findsOneWidget);
    expect(api.setUrlCalls, 1);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Vendas'), findsOneWidget);
    expect(find.text('Sem conteúdo'), findsOneWidget);
  });

  testWidgets('TV offline: recarregar desabilitado e aviso "quando conectar"',
      (tester) async {
    await openDetail(tester, 'Zeta');

    final reload = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Recarregar'),
    );
    expect(reload.onPressed, isNull);

    await tester.enterText(
      field('Endereço do site'),
      'https://example.local/vendas',
    );
    await tester.tap(find.text('Exibir nesta TV'));
    await tester.pumpAndSettle();

    expect(
      find.text('Conteúdo salvo. A TV vai exibir quando conectar.'),
      findsOneWidget,
    );
  });

  testWidgets('Identificar manda o comando', (tester) async {
    await openDetail(tester, 'Recepção');

    await tester.tap(find.text('Identificar'));
    await tester.pumpAndSettle();

    expect(api.commands, [('b', 'identify')]);
    expect(find.text('Olhe para a TV.'), findsOneWidget);
  });

  testWidgets('Desparear pede confirmação', (tester) async {
    await openDetail(tester, 'Recepção');

    await tester.tap(find.text('Desparear'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(api.commands, isEmpty);

    await tester.tap(find.text('Desparear'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remover'));
    await tester.pumpAndSettle();

    expect(api.commands, [('b', 'unpair')]);
    expect(find.text('Status'), findsNothing);
    expect(find.text('Zeta'), findsOneWidget);
    expect(find.text('Recepção'), findsNothing);
  });

  testWidgets('device.removed da TV aberta mostra "TV não encontrada."',
      (tester) async {
    await openDetail(tester, 'Recepção');

    socket.emit(
      Envelope.create(MessageTypes.deviceRemoved, payload: {'deviceId': 'b'}),
    );
    await tester.pumpAndSettle();

    expect(find.text('TV não encontrada.'), findsOneWidget);
    await tester.tap(find.text('Voltar para a lista'));
    await tester.pumpAndSettle();
    expect(find.text('Zeta'), findsOneWidget);
  });

  testWidgets('Parar de exibir limpa o conteúdo', (tester) async {
    await openDetail(tester, 'Recepção');
    await tester.enterText(
      field('Endereço do site'),
      'https://example.local/vendas',
    );
    await tester.tap(find.text('Exibir nesta TV'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Parar de exibir'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Parar'));
    await tester.pumpAndSettle();

    expect(find.text('Parar de exibir'), findsNothing);
    expect(
      api.devices.firstWhere((d) => d.id == 'b').content,
      isNull,
    );
  });

  testWidgets('atribuir uma playlist chama setDevicePlaylist e mostra o nome',
      (tester) async {
    api.playlists.add(
      Playlist(
        id: 'p1',
        name: 'Recepção manhã',
        createdAt: DateTime.utc(2026, 10, 1),
      ),
    );
    await openDetail(tester, 'Recepção');
    expect(find.text('Nada atribuído.'), findsOneWidget);

    await tester.tap(find.byType(DropdownMenu<PlaylistSummary>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recepção manhã').last);
    await tester.pumpAndSettle();

    expect(api.playlistAssignments, [('b', 'p1')]);
    expect(find.text('Atribuído: Playlist: Recepção manhã'), findsOneWidget);
    expect(find.text('Parar de exibir'), findsOneWidget);
  });

  testWidgets('mostra a playlist atual e "Parar de exibir" a limpa',
      (tester) async {
    api.playlists.add(
      Playlist(
        id: 'p1',
        name: 'Recepção manhã',
        createdAt: DateTime.utc(2026, 10, 1),
      ),
    );
    final b = api.devices[1];
    api.devices[1] = DeviceSummary(
      id: b.id,
      name: b.name,
      online: b.online,
      createdAt: b.createdAt,
      info: b.info,
      lastSeenAt: b.lastSeenAt,
      currentItem: b.currentItem,
      playlist: const PlaylistRef(id: 'p1', name: 'Recepção manhã'),
    );
    await openDetail(tester, 'Recepção');
    expect(find.text('Atribuído: Playlist: Recepção manhã'), findsOneWidget);

    await tester.tap(find.text('Parar de exibir'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Parar'));
    await tester.pumpAndSettle();

    expect(find.text('Nada atribuído.'), findsOneWidget);
    expect(api.devices[1].playlist, isNull);
  });

  testWidgets('escolher mídia da biblioteca atribui a mídia', (tester) async {
    api.media.addAll(sampleMedia());
    await openDetail(tester, 'Recepção');

    await tester.tap(find.byType(DropdownMenu<Media>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Promoção').last);
    await tester.pumpAndSettle();

    expect(api.devices[1].content?.mediaId, 'img');
    expect(find.text('Atribuído: Promoção'), findsOneWidget);
  });
}
