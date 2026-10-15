import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:test/test.dart';

import '../support/realtime_support.dart';
import '../support/test_server.dart';

void main() {
  late TestServer server;
  late Map<String, String> admin;
  late ({String id, String token}) tv;

  setUp(() async {
    server = await TestServer.start();
    admin = await setupAdmin(server);
    tv = insertDevice(server);
  });

  test('DELETE /device remove a TV, avisa o painel e fecha com 4401', () async {
    final inbox = Inbox(await connectDevice(server, tv.token));
    sendHello(inbox.channel);
    await inbox.nextOfType(MessageTypes.contentSync);
    final adminInbox = Inbox(await connectAdmin(server, admin));

    // Sem Origin, como faz o app da TV.
    final response = await server.send(
      'DELETE',
      '/api/v1/device',
      headers: {'authorization': 'Bearer ${tv.token}'},
    );

    expect(response.statusCode, 204);
    final removed = await adminInbox.nextOfType(MessageTypes.deviceRemoved);
    expect(removed.payload, {'deviceId': tv.id});
    expect(await inbox.closeCode(), WsCloseCodes.unauthorized);
    final list =
        jsonBody(await server.get('/api/v1/devices', headers: admin))! as Map;
    expect(list['devices'], isEmpty);
  });

  test('TV offline também se despareia, uma vez só', () async {
    final headers = {'authorization': 'Bearer ${tv.token}'};
    expect(
      (await server.send(
        'DELETE',
        '/api/v1/device',
        headers: headers,
      )).statusCode,
      204,
    );
    expect(
      (await server.send(
        'DELETE',
        '/api/v1/device',
        headers: headers,
      )).statusCode,
      401,
    );
  });

  test('sem token, token errado ou cookie de admin: 401', () async {
    for (final headers in <Map<String, String>>[
      {},
      {'authorization': 'Bearer errado'},
      {'authorization': 'Basic abc'},
      admin,
    ]) {
      final r = await server.send('DELETE', '/api/v1/device', headers: headers);
      expect(r.statusCode, 401, reason: '$headers');
      expect(errorCode(r), 'unauthorized');
    }
    final list =
        jsonBody(await server.get('/api/v1/devices', headers: admin))! as Map;
    expect(list['devices'], hasLength(1));
  });
}
