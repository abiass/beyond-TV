import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_server/server.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/realtime_support.dart';
import '../support/test_server.dart';

void main() {
  late FakeClock clock;
  late TestServer server;
  late Map<String, String> admin;

  const deviceInfo = DeviceInfo(
    appVersion: '1.1.0',
    manufacturer: 'TCL',
    model: '43P635',
  );

  setUp(() async {
    clock = FakeClock();
    server = await TestServer.start(clock: clock.call);
    admin = await setupAdmin(server);
  });

  tearDown(() => server.close());

  Future<PairRequestTicket> request() async {
    final response = await server.post(
      '/api/v1/pair-requests',
      json: {'deviceInfo': deviceInfo.toJson()},
    );
    expect(response.statusCode, 201, reason: response.body);
    return PairRequestTicket.fromJson(
      jsonBody(response)! as Map<String, Object?>,
    );
  }

  Map<String, String> bearer(PairRequestTicket ticket) => {
    'authorization': 'Bearer ${ticket.secret}',
  };

  Future<http.Response> poll(PairRequestTicket ticket) =>
      server.get('/api/v1/pair-requests/${ticket.id}', headers: bearer(ticket));

  Future<PairRequestPoll> pollOk(PairRequestTicket ticket) async {
    final response = await poll(ticket);
    expect(response.statusCode, 200, reason: response.body);
    return PairRequestPoll.fromJson(
      jsonBody(response)! as Map<String, Object?>,
    );
  }

  Future<List<PendingPairRequest>> pending() async {
    final response = await server.get('/api/v1/pair-requests', headers: admin);
    expect(response.statusCode, 200);
    return [
      for (final json in (jsonBody(response)! as Map)['requests'] as List)
        PendingPairRequest.fromJson(json as Map<String, Object?>),
    ];
  }

  Future<http.Response> decide(PairRequestTicket ticket, String action) =>
      server.post('/api/v1/pair-requests/${ticket.id}/$action', headers: admin);

  test(
    'a TV abre o pedido e o painel o vê com o código de conferência',
    () async {
      final ticket = await request();

      expect(ticket.confirmCode, matches(RegExp(r'^\d{4}$')));
      expect(ticket.secret, isNotEmpty);

      final list = await pending();
      expect(list.single.id, ticket.id);
      expect(list.single.confirmCode, ticket.confirmCode);
      expect(list.single.deviceInfo, deviceInfo);
      expect(list.single.ip, isNotEmpty);
      expect((await pollOk(ticket)).status, PairRequestStatus.pending);
    },
  );

  test(
    'aprovar cadastra a TV e entrega as credenciais uma única vez',
    () async {
      final ticket = await request();

      final approved = await decide(ticket, 'approve');

      expect(approved.statusCode, 200, reason: approved.body);
      final summary = DeviceSummary.fromJson(
        jsonBody(approved)! as Map<String, Object?>,
      );
      expect(summary.name, 'TCL 43P635');

      final result = await pollOk(ticket);
      expect(result.status, PairRequestStatus.approved);
      final credentials = result.credentials!;
      expect(credentials.deviceId, summary.id);
      final device = server.db.select('SELECT * FROM devices').single;
      expect(device['token_hash'], hashToken(credentials.deviceToken));

      // Entregues as credenciais, o pedido some.
      expect((await poll(ticket)).statusCode, 404);
      expect(await pending(), isEmpty);
    },
  );

  test('a TV aprovada conecta no tempo real com o token recebido', () async {
    final ticket = await request();
    await decide(ticket, 'approve');
    final credentials = (await pollOk(ticket)).credentials!;

    final channel = await connectDevice(server, credentials.deviceToken);
    sendHello(channel);
    final inbox = Inbox(channel);

    expect(
      (await inbox.nextOfType(MessageTypes.contentSync)).type,
      MessageTypes.contentSync,
    );
  });

  test('recusar avisa a TV e não cadastra nada', () async {
    final ticket = await request();

    expect((await decide(ticket, 'reject')).statusCode, 204);

    expect((await pollOk(ticket)).status, PairRequestStatus.rejected);
    expect(await pending(), isEmpty);
    expect(server.db.select('SELECT * FROM devices'), isEmpty);
    expect((await decide(ticket, 'approve')).statusCode, 404);
  });

  test('vence em 10 minutos', () async {
    final ticket = await request();

    clock.advance(pairRequestTtl);

    expect((await pollOk(ticket)).status, PairRequestStatus.expired);
    expect(await pending(), isEmpty);
    expect((await decide(ticket, 'approve')).statusCode, 404);
  });

  test('segredo errado ou ausente responde como pedido inexistente', () async {
    final ticket = await request();

    final wrong = await server.get(
      '/api/v1/pair-requests/${ticket.id}',
      headers: {'authorization': 'Bearer outro'},
    );
    final missing = await server.get('/api/v1/pair-requests/${ticket.id}');

    expect(wrong.statusCode, 404);
    expect(missing.statusCode, 404);
  });

  test('um pedido novo do mesmo IP substitui o anterior', () async {
    final first = await request();
    final second = await request();

    expect((await poll(first)).statusCode, 404);
    expect((await pending()).single.id, second.id);
  });

  test('a TV pode desistir do pedido', () async {
    final ticket = await request();

    final response = await server.send(
      'DELETE',
      '/api/v1/pair-requests/${ticket.id}',
      headers: bearer(ticket),
    );

    expect(response.statusCode, 204);
    expect(await pending(), isEmpty);
  });

  test('listar, aprovar e recusar exigem o administrador', () async {
    final ticket = await request();

    expect((await server.get('/api/v1/pair-requests')).statusCode, 401);
    expect(
      (await server.post(
        '/api/v1/pair-requests/${ticket.id}/approve',
      )).statusCode,
      401,
    );
    expect(
      (await server.post(
        '/api/v1/pair-requests/${ticket.id}/reject',
      )).statusCode,
      401,
    );
  });

  test('cada IP abre no máximo 5 pedidos por minuto', () async {
    for (var i = 0; i < PairRequestsApi.maxCreateAttempts; i++) {
      await request();
    }

    final blocked = await server.post(
      '/api/v1/pair-requests',
      json: {'deviceInfo': deviceInfo.toJson()},
    );

    expect(blocked.statusCode, 429);
    expect(blocked.headers['retry-after'], isNotNull);
  });

  test('pedido sem deviceInfo é recusado', () async {
    final response = await server.post('/api/v1/pair-requests', json: {});

    expect(response.statusCode, 400);
  });

  test('o painel recebe o pedido e o fechamento ao vivo', () async {
    final inbox = Inbox(await connectAdmin(server, admin));

    final ticket = await request();
    final created = await inbox.nextOfType(MessageTypes.pairRequestCreated);
    expect(PendingPairRequest.fromJson(created.payload).id, ticket.id);

    await decide(ticket, 'approve');
    final closed = await inbox.nextOfType(MessageTypes.pairRequestClosed);
    expect(closed.payload, {'id': ticket.id});
    final paired = await inbox.nextOfType(MessageTypes.devicePaired);
    expect(DeviceSummary.fromJson(paired.payload).name, 'TCL 43P635');
  });
}
