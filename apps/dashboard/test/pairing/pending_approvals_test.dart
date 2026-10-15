import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_admin_socket.dart';
import '../support/fake_api.dart';

PendingPairRequest pendingTv(
  String id, {
  String code = '4821',
  String model = '43P635',
  Duration expiresIn = const Duration(minutes: 10),
}) =>
    PendingPairRequest(
      id: id,
      confirmCode: code,
      deviceInfo: DeviceInfo(
        appVersion: '1.1.0',
        manufacturer: 'TCL',
        model: model,
        androidVersion: '11',
      ),
      ip: '192.168.0.42',
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(expiresIn),
    );

void main() {
  late FakeApi api;
  late FakeAdminSocket socket;

  setUp(() {
    api = FakeApi(adminPassword: 'senha-forte-1', loggedIn: true);
    socket = FakeAdminSocket();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(dashboardWith(api, socket: socket));
    await tester.pumpAndSettle();
  }

  testWidgets('sem TVs: o pedido aparece com código, modelo e IP', (
    tester,
  ) async {
    api.pairRequests.add(pendingTv('r1'));
    await open(tester);

    expect(find.text('Aguardando aprovação (1)'), findsOneWidget);
    expect(find.text('TCL 43P635'), findsOneWidget);
    expect(find.text('4821'), findsOneWidget);
    expect(find.text('IP 192.168.0.42 · Android 11'), findsOneWidget);
    expect(find.text('Nenhuma TV pareada ainda.'), findsOneWidget);
  });

  testWidgets('sem pedidos, a seção não aparece', (tester) async {
    await open(tester);

    expect(find.textContaining('Aguardando aprovação'), findsNothing);
  });

  testWidgets('Aprovar pareia a TV e ela entra na lista', (tester) async {
    api.pairRequests.add(pendingTv('r1'));
    await open(tester);

    await tester.tap(find.text('Aprovar'));
    await tester.pumpAndSettle();

    expect(api.approved, ['r1']);
    expect(find.textContaining('Aguardando aprovação'), findsNothing);
    expect(find.text('"TCL 43P635" foi pareada.'), findsOneWidget);
    // A TV já aparece na lista (sem esperar o device.paired).
    expect(find.text('TCL 43P635'), findsOneWidget);
    expect(find.text('Nenhuma TV pareada ainda.'), findsNothing);
  });

  testWidgets('Recusar tira o pedido da lista', (tester) async {
    api.pairRequests.add(pendingTv('r1'));
    await open(tester);

    await tester.tap(find.text('Recusar'));
    await tester.pumpAndSettle();

    expect(api.rejected, ['r1']);
    expect(find.textContaining('Aguardando aprovação'), findsNothing);
    expect(find.text('Pedido recusado.'), findsOneWidget);
  });

  testWidgets('pedido que já venceu no servidor sai da lista com aviso', (
    tester,
  ) async {
    api.pairRequests.add(pendingTv('r1'));
    await open(tester);
    api.pairRequests.clear(); // O servidor já esqueceu o pedido (404).

    await tester.tap(find.text('Aprovar'));
    await tester.pumpAndSettle();

    expect(find.text('Pedido não encontrado.'), findsOneWidget);
    expect(find.textContaining('Aguardando aprovação'), findsNothing);
  });

  testWidgets('pedidos chegam e saem ao vivo', (tester) async {
    await open(tester);

    socket.emit(
      Envelope.create(
        MessageTypes.pairRequestCreated,
        payload: pendingTv('r1').toJson(),
      ),
    );
    socket.emit(
      Envelope.create(
        MessageTypes.pairRequestCreated,
        payload: pendingTv('r2', code: '0042', model: 'TV Box').toJson(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Aguardando aprovação (2)'), findsOneWidget);

    socket.emit(
      Envelope.create(MessageTypes.pairRequestClosed, payload: {'id': 'r1'}),
    );
    await tester.pumpAndSettle();
    expect(find.text('Aguardando aprovação (1)'), findsOneWidget);
    expect(find.text('0042'), findsOneWidget);
    expect(find.text('4821'), findsNothing);
  });

  testWidgets('pedidos vencidos somem sozinhos', (tester) async {
    api.pairRequests.add(
      pendingTv('r1', expiresIn: const Duration(seconds: 10)),
    );
    await open(tester);
    expect(find.text('Aguardando aprovação (1)'), findsOneWidget);

    // O relógio do teste anda junto com os timers.
    await tester.pump(const Duration(seconds: 16));

    expect(find.textContaining('Aguardando aprovação'), findsNothing);
  });

  testWidgets('aparece também acima da lista de TVs', (tester) async {
    api.devices.add(
      DeviceSummary(
        id: 'a',
        name: 'Recepção',
        online: true,
        createdAt: DateTime.utc(2026, 10, 1),
      ),
    );
    api.pairRequests.add(pendingTv('r1'));
    await open(tester);

    expect(
      tester.getTopLeft(find.text('Aguardando aprovação (1)')).dy,
      lessThan(tester.getTopLeft(find.text('Recepção')).dy),
    );
  });
}
