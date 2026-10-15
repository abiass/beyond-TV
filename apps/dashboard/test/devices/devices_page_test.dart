import 'package:beyond_dashboard/src/api/api_client.dart';
import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_admin_socket.dart';
import '../support/fake_api.dart';

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
      ),
      lastSeenAt: DateTime.now().subtract(const Duration(minutes: 5)),
      currentItem: online ? 'https://example.local/painel' : null,
    );

Envelope event(String type, Map<String, Object?> payload) =>
    Envelope.create(type, payload: payload);

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

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(dashboardWith(api, socket: socket));
    await tester.pumpAndSettle();
  }

  Finder dot(String status) => find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == status,
      );

  testWidgets('mostra as TVs com a online primeiro', (tester) async {
    await open(tester);

    expect(find.text('Ao vivo'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Recepção')).dy,
      lessThan(tester.getTopLeft(find.text('Zeta')).dy),
    );
    expect(find.text('https://example.local/painel'), findsOneWidget);
    expect(find.textContaining('Acme TV 4K · Android 11'), findsNWidgets(2));
    expect(find.textContaining('visto há 5 min'), findsOneWidget);
    expect(dot('online'), findsOneWidget);
    expect(dot('offline'), findsOneWidget);
  });

  testWidgets('device.offline deixa a TV offline com "visto há"',
      (tester) async {
    await open(tester);

    socket.emit(
      event(MessageTypes.deviceOffline, {
        'deviceId': 'b',
        'lastSeenAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    await tester.pumpAndSettle();

    expect(dot('online'), findsNothing);
    expect(dot('offline'), findsNWidgets(2));
    expect(find.textContaining('visto agora há pouco'), findsOneWidget);
    expect(find.text('https://example.local/painel'), findsNothing);
  });

  testWidgets('device.paired mostra a TV nova', (tester) async {
    await open(tester);

    socket
        .emit(event(MessageTypes.devicePaired, tv('c', 'Sala nova').toJson()));
    await tester.pumpAndSettle();

    expect(find.text('Sala nova'), findsOneWidget);
  });

  testWidgets('device.removed tira a TV', (tester) async {
    await open(tester);

    socket.emit(event(MessageTypes.deviceRemoved, {'deviceId': 'a'}));
    await tester.pumpAndSettle();

    expect(find.text('Zeta'), findsNothing);
    expect(find.text('Recepção'), findsOneWidget);
  });

  testWidgets('fechar com 4401 leva ao login', (tester) async {
    await open(tester);

    socket.closeWith(WsCloseCodes.unauthorized);
    await tester.pumpAndSettle();

    expect(find.text('Zeta'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Usuário'), findsOneWidget);
  });

  Future<void> openMenu(WidgetTester tester, String name) async {
    final tile = find.ancestor(
      of: find.text(name),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: tile, matching: find.byTooltip('Ações')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renomear atualiza o nome na lista', (tester) async {
    await open(tester);

    await openMenu(tester, 'Zeta');
    await tester.tap(find.text('Renomear'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '  Cozinha ');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Cozinha'), findsOneWidget);
    expect(find.text('Zeta'), findsNothing);
  });

  testWidgets('nome vazio não é enviado', (tester) async {
    await open(tester);

    await openMenu(tester, 'Zeta');
    await tester.tap(find.text('Renomear'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('O nome deve ter de 1 a 64 caracteres.'), findsOneWidget);
    expect(api.devices.map((d) => d.name), contains('Zeta'));
  });

  testWidgets('erro da API aparece no diálogo de renomear', (tester) async {
    await open(tester);

    await openMenu(tester, 'Zeta');
    await tester.tap(find.text('Renomear'));
    await tester.pumpAndSettle();
    api.failure = const ApiException('Nome inválido.', status: 400);
    await tester.enterText(find.byType(TextFormField), 'Outra');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Nome inválido.'), findsOneWidget);
  });

  testWidgets('remover pede confirmação; cancelar não remove', (tester) async {
    await open(tester);

    await openMenu(tester, 'Zeta');
    await tester.tap(find.text('Remover'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Remover Zeta?'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Zeta'), findsOneWidget);
    expect(api.devices, hasLength(2));

    await openMenu(tester, 'Zeta');
    await tester.tap(find.text('Remover'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remover'));
    await tester.pumpAndSettle();

    expect(find.text('Zeta'), findsNothing);
    expect(find.text('TV removida.'), findsOneWidget);
    expect(api.devices, hasLength(1));
  });
}
