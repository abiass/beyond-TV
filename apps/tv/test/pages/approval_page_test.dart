import 'dart:convert';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_tv/src/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fake_socket.dart';
import '../support/fakes.dart';

void main() {
  late MemoryCredentialStore store;
  late List<http.Request> requests;

  /// Situações devolvidas, em ordem, a cada consulta da TV; a última se
  /// repete.
  late List<PairRequestPoll> polls;
  late int created;

  const credentials = PairResponse(
    deviceId: 'tv1',
    deviceToken: 'token',
    serverId: 'abc',
  );

  setUp(() {
    store = MemoryCredentialStore();
    requests = [];
    polls = [const PairRequestPoll(PairRequestStatus.pending)];
    created = 0;
  });

  http.Response ticketResponse(http.Request request) {
    created++;
    return http.Response(
      jsonEncode(
        PairRequestTicket(
          id: 'r$created',
          secret: 'segredo$created',
          confirmCode: '48${created}1',
          expiresAt: DateTime.utc(2030),
        ).toJson(),
      ),
      201,
    );
  }

  http.Response pollResponse(http.Request request) {
    final next = polls.length > 1 ? polls.removeAt(0) : polls.single;
    return http.Response(jsonEncode(next.toJson()), 200);
  }

  http.Response noContent(http.Request request) => http.Response('', 204);

  /// Rotas do pedido. Registra as requisições na lista do teste atual: o
  /// cancelamento ao descartar a tela chega depois do fim do teste.
  Map<String, http.Response Function(http.Request)> approvalRoutes() {
    final log = requests;
    http.Response Function(http.Request) logged(
      http.Response Function(http.Request) handler,
    ) =>
        (request) {
          log.add(request);
          return handler(request);
        };
    return {
      'POST /api/v1/pair-requests': logged(ticketResponse),
      'GET /api/v1/pair-requests/r1': logged(pollResponse),
      'GET /api/v1/pair-requests/r2': logged(pollResponse),
      'DELETE /api/v1/pair-requests/r1': logged(noContent),
      'DELETE /api/v1/pair-requests/r2': logged(noContent),
    };
  }

  /// Abre o app, escolhe o PC-SALA e espera a tela de aprovação.
  Future<void> openApproval(
    WidgetTester tester, {
    Map<String, http.Response Function(http.Request)>? routes,
  }) async {
    useTvScreen(tester);
    await tester.pumpWidget(
      TvApp(
        mediaRoot: fakeMediaRoot,
        credentials: store,
        discovery: FakeDiscovery([pcSala]),
        deviceInfo: const FakeDeviceInfo(),
        connector: FakeConnector().call,
        api: fakeApi(routes: routes ?? approvalRoutes()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('PC-SALA'));
    await settle(tester);
  }

  /// Avança [seconds] segundos (a tela consulta a cada 2 s). Sem
  /// pumpAndSettle: o indicador de espera gira sem parar.
  Future<void> wait(WidgetTester tester, int seconds) async {
    for (var i = 0; i < seconds * 2; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  testWidgets('mostra o código de conferência e o nome da TV', (
    tester,
  ) async {
    await openApproval(tester);

    expect(find.text('Aguardando aprovação…'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('^Código de conferência: 4811')),
      findsOne,
    );
    expect(find.textContaining('TV: Acme X1'), findsOneWidget);
    final body = jsonDecode(requests.first.body) as Map<String, Object?>;
    expect(body['deviceInfo'], containsPair('model', 'X1'));
  });

  testWidgets('aprovado no painel: salva as credenciais e entra', (
    tester,
  ) async {
    polls = [
      const PairRequestPoll(PairRequestStatus.pending),
      const PairRequestPoll(
        PairRequestStatus.approved,
        credentials: credentials,
      ),
    ];
    await openApproval(tester);

    await wait(tester, 5);
    await tester.pumpAndSettle();

    expect(store.saved?.deviceToken, 'token');
    expect(store.saved?.server.serverId, 'abc');
    final poll = requests.firstWhere((r) => r.method == 'GET');
    expect(poll.headers['Authorization'], 'Bearer segredo1');
    // Pareou: não cancela o pedido ao sair da tela.
    expect(requests.map((r) => r.method), isNot(contains('DELETE')));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('recusado: avisa e permite pedir de novo', (tester) async {
    polls = [const PairRequestPoll(PairRequestStatus.rejected)];
    await openApproval(tester);

    await wait(tester, 3);

    expect(find.text('O pedido foi recusado no painel.'), findsOneWidget);
    polls = [const PairRequestPoll(PairRequestStatus.pending)];
    await tester.tap(find.text('Pedir de novo'));
    await wait(tester, 1);

    expect(created, 2);
    expect(
      find.bySemanticsLabel(RegExp('^Código de conferência: 4821')),
      findsOne,
    );
  });

  testWidgets('vencido: pede de novo sozinho, com outro código', (
    tester,
  ) async {
    polls = [
      const PairRequestPoll(PairRequestStatus.expired),
      const PairRequestPoll(PairRequestStatus.pending),
    ];
    await openApproval(tester);

    await wait(tester, 3);

    expect(created, 2);
    expect(
      find.bySemanticsLabel(RegExp('^Código de conferência: 4821')),
      findsOne,
    );
  });

  testWidgets('"Digitar código" abre o teclado e cancela o pedido', (
    tester,
  ) async {
    await openApproval(tester);

    await tester.tap(find.text('Digitar código'));
    await tester.pumpAndSettle();

    expect(find.textContaining('digite aqui o código'), findsOneWidget);
    expect(
      requests.where((r) => r.method == 'DELETE').single.url.path,
      '/api/v1/pair-requests/r1',
    );
  });

  testWidgets('servidor sem aprovação no painel cai no código digitado', (
    tester,
  ) async {
    // Sem as rotas novas, o servidor falso responde 404 (como a 1.0).
    await openApproval(tester, routes: const {});
    await tester.pumpAndSettle();

    expect(find.textContaining('digite aqui o código'), findsOneWidget);
  });
}

/// Termina a transição de tela sem esperar o indicador de espera parar.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}
