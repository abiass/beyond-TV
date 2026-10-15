import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/realtime_support.dart';
import '../support/test_server.dart';

void main() {
  late TestServer server;
  late Map<String, String> admin;

  setUp(() async {
    server = await TestServer.start();
    admin = await setupAdmin(server);
  });

  Future<List<Object?>> devices() async =>
      (jsonBody(await server.get('/api/v1/devices', headers: admin))!
              as Map)['devices']
          as List<Object?>;

  Future<http.Response> patch(
    String id,
    Object? body, {
    Map<String, String>? h,
  }) => server.send(
    'PATCH',
    '/api/v1/devices/$id',
    json: body,
    headers: h ?? admin,
  );

  test('rotas exigem sessão', () async {
    final tv = insertDevice(server);

    expect((await server.get('/api/v1/devices')).statusCode, 401);
    expect(
      (await server.send('PATCH', '/api/v1/devices/${tv.id}')).statusCode,
      401,
    );
    expect(
      (await server.send('DELETE', '/api/v1/devices/${tv.id}')).statusCode,
      401,
    );
  });

  test('lista vazia', () async {
    expect(await devices(), isEmpty);
  });

  test('lista a TV com o estado offline', () async {
    final tv = insertDevice(server);

    final list = await devices();

    final summary = DeviceSummary.fromJson(
      (list.single! as Map).cast<String, Object?>(),
    );
    expect(summary.id, tv.id);
    expect(summary.name, 'Recepção');
    expect(summary.online, isFalse);
    expect(summary.info?.appVersion, '0.5.0');
  });

  test('PATCH renomeia e avisa o dashboard', () async {
    final tv = insertDevice(server);
    final inbox = Inbox(await connectAdmin(server, admin));

    final response = await patch(tv.id, {'name': '  Sala de espera  '});

    expect(response.statusCode, 200);
    expect((jsonBody(response)! as Map)['name'], 'Sala de espera');
    final event = await inbox.next();
    expect(event.type, MessageTypes.deviceState);
    expect(event.payload['name'], 'Sala de espera');
    expect((await devices()).length, 1);
  });

  test('PATCH recusa nome vazio ou com mais de 64 caracteres', () async {
    final tv = insertDevice(server);

    expect((await patch(tv.id, {'name': '   '})).statusCode, 400);
    expect((await patch(tv.id, {'name': 'a' * 65})).statusCode, 400);
    expect((await patch(tv.id, {'name': 'a' * 64})).statusCode, 200);
    expect((await patch(tv.id, {})).statusCode, 400);
  });

  test('PATCH de TV inexistente responde 404', () async {
    expect((await patch('nao-existe', {'name': 'X'})).statusCode, 404);
  });

  test('DELETE remove a TV, derruba o WebSocket e avisa o dashboard', () async {
    final tv = insertDevice(server);
    final channel = await connectDevice(server, tv.token);
    final tvInbox = Inbox(channel);
    sendHello(channel);
    final adminInbox = Inbox(await connectAdmin(server, admin));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final response = await server.send(
      'DELETE',
      '/api/v1/devices/${tv.id}',
      headers: admin,
    );

    expect(response.statusCode, 204);
    expect(await tvInbox.closeCode(), WsCloseCodes.unauthorized);
    final removed = await adminInbox.next();
    expect(removed.type, MessageTypes.deviceRemoved);
    expect(removed.payload, {'deviceId': tv.id});
    expect(await devices(), isEmpty);
    expect(
      (await server.send(
        'DELETE',
        '/api/v1/devices/${tv.id}',
        headers: admin,
      )).statusCode,
      404,
    );
  });

  test('PATCH e DELETE de outra origem recebem 403', () async {
    final tv = insertDevice(server);
    final evil = {...admin, 'origin': 'http://evil.example'};

    final renamed = await patch(tv.id, {'name': 'X'}, h: evil);
    final deleted = await server.send(
      'DELETE',
      '/api/v1/devices/${tv.id}',
      headers: evil,
    );

    expect(renamed.statusCode, 403);
    expect(deleted.statusCode, 403);
    expect(await devices(), hasLength(1));
  });
}
