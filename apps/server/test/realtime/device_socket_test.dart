import 'dart:convert';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_server/server.dart';
import 'package:test/test.dart';

import '../support/realtime_support.dart';
import '../support/test_server.dart';

const _short = Duration(milliseconds: 200);

void main() {
  late TestServer server;
  late Map<String, String> admin;
  late ({String id, String token}) tv;

  setUp(() async {
    server = await TestServer.start(
      handler: (db, mediaDir) => buildHandler(
        db: db,
        mediaDir: mediaDir,
        hasher: fastHasher,
        timeouts: const RealtimeTimeouts(hello: _short, silence: _short),
      ),
    );
    admin = await setupAdmin(server);
    tv = insertDevice(server);
  });

  Future<List<Map<String, Object?>>> listDevices() async {
    final response = await server.get('/api/v1/devices', headers: admin);
    return ((jsonBody(response)! as Map)['devices'] as List)
        .cast<Map<String, Object?>>();
  }

  test('token errado fecha com 4401', () async {
    final inbox = Inbox(await connectDevice(server, 'errado'));

    expect(await inbox.closeCode(), WsCloseCodes.unauthorized);
  });

  test('sem token fecha com 4401', () async {
    final inbox = Inbox(await connectDevice(server, null));

    expect(await inbox.closeCode(), WsCloseCodes.unauthorized);
  });

  test('sem hello a tempo fecha com 4400', () async {
    final inbox = Inbox(await connectDevice(server, tv.token));

    expect(await inbox.closeCode(), WsCloseCodes.protocolError);
  });

  test('primeira mensagem diferente de hello fecha com 4400', () async {
    final channel = await connectDevice(server, tv.token);
    final inbox = Inbox(channel);
    channel.sink.add(
      Envelope.create(
        MessageTypes.heartbeat,
        payload: {'uptimeSeconds': 1},
      ).encode(),
    );

    expect(await inbox.closeCode(), WsCloseCodes.protocolError);
  });

  test('versão de protocolo diferente recebe error e 4426', () async {
    final channel = await connectDevice(server, tv.token);
    final inbox = Inbox(channel);
    channel.sink.add(helloEnvelope(v: 99).encode());

    final error = await inbox.next();
    expect(error.type, MessageTypes.error);
    expect(error.payload['code'], 'incompatible_version');
    expect(await inbox.closeCode(), WsCloseCodes.incompatibleVersion);
  });

  test('hello grava o info e deixa a TV online', () async {
    final channel = await connectDevice(server, tv.token);
    sendHello(channel, currentItem: 'https://example.local/painel');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final devices = await listDevices();
    expect(devices.single['online'], isTrue);
    expect(devices.single['currentItem'], 'https://example.local/painel');
    expect(devices.single['lastSeenAt'], isNotNull);
    final row = server.db.select('SELECT info FROM devices WHERE id = ?', [
      tv.id,
    ]).single;
    expect(jsonDecode(row['info'] as String), testDeviceInfo.toJson());
  });

  test('fechar a conexão deixa a TV offline', () async {
    final channel = await connectDevice(server, tv.token);
    sendHello(channel);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect((await listDevices()).single['online'], isTrue);

    await channel.sink.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final device = (await listDevices()).single;
    expect(device['online'], isFalse);
    expect(device['currentItem'], isNull);
  });

  test('segunda conexão derruba a primeira com 4409', () async {
    final first = await connectDevice(server, tv.token);
    final firstInbox = Inbox(first);
    sendHello(first);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final second = await connectDevice(server, tv.token);
    sendHello(second);

    expect(await firstInbox.closeCode(), WsCloseCodes.replaced);
    expect((await listDevices()).single['online'], isTrue);
  });

  test('silêncio depois do hello fecha com 4400', () async {
    final channel = await connectDevice(server, tv.token);
    final inbox = Inbox(channel);
    sendHello(channel);

    expect(await inbox.closeCode(), WsCloseCodes.protocolError);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect((await listDevices()).single['online'], isFalse);
  });

  test('heartbeat mantém a conexão e atualiza o currentItem', () async {
    final channel = await connectDevice(server, tv.token);
    sendHello(channel);
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      channel.sink.add(
        Envelope.create(
          MessageTypes.heartbeat,
          payload: {'uptimeSeconds': i, 'currentItem': 'item-$i'},
        ).encode(),
      );
    }

    final device = (await listDevices()).single;
    expect(device['online'], isTrue);
    expect(device['currentItem'], 'item-3');
  });
}
