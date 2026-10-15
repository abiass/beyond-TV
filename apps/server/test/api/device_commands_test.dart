import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:http/http.dart' as http;
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

  Future<http.Response> command(Object type, {String? id}) => server.post(
    '/api/v1/devices/${id ?? tv.id}/commands',
    json: {'type': type},
    headers: admin,
  );

  Future<(Inbox, dynamic)> connectTv() async {
    final channel = await connectDevice(server, tv.token);
    final inbox = Inbox(channel);
    sendHello(channel);
    await inbox.nextOfType(MessageTypes.contentSync);
    return (inbox, channel);
  }

  test('reload e identify chegam à TV online', () async {
    final (inbox, _) = await connectTv();

    expect((await command('reload')).statusCode, 202);
    final reload = await inbox.nextOfType(MessageTypes.cmdReload);
    expect(reload.payload, isEmpty);

    expect((await command('identify')).statusCode, 202);
    final identify = await inbox.nextOfType(MessageTypes.cmdIdentify);
    expect(identify.payload['name'], 'Recepção');
    expect(identify.payload['durationSeconds'], 10);
  });

  test('TV offline responde 409', () async {
    for (final type in ['reload', 'identify']) {
      final r = await command(type);
      expect(r.statusCode, 409);
      expect(errorCode(r), 'device_offline');
    }
  });

  test('tipo inválido e TV inexistente', () async {
    expect((await command('format')).statusCode, 400);
    expect((await command(1)).statusCode, 400);
    expect((await command('reload', id: 'nada')).statusCode, 404);
  });

  test('unpair manda cmd.unpair, fecha com 4401 e remove a TV', () async {
    final (inbox, _) = await connectTv();
    final adminInbox = Inbox(await connectAdmin(server, admin));

    expect((await command('unpair')).statusCode, 202);

    expect((await inbox.next()).type, MessageTypes.cmdUnpair);
    expect(await inbox.closeCode(), WsCloseCodes.unauthorized);
    final removed = await adminInbox.nextOfType(MessageTypes.deviceRemoved);
    expect(removed.payload, {'deviceId': tv.id});
    final list =
        jsonBody(await server.get('/api/v1/devices', headers: admin))! as Map;
    expect(list['devices'], isEmpty);
  });

  test('unpair de TV offline remove a TV', () async {
    expect((await command('unpair')).statusCode, 202);
    expect((await command('unpair')).statusCode, 404);
  });

  test('ack da TV não derruba a conexão', () async {
    final (inbox, channel) = await connectTv();

    channel.sink.add(
      Envelope.create(MessageTypes.ack, payload: {'ref': 'x'}).encode(),
    );
    channel.sink.add(
      Envelope.create(MessageTypes.ack, payload: {'nope': 1}).encode(),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect((await command('reload')).statusCode, 202);
    await inbox.nextOfType(MessageTypes.cmdReload);
  });
}
