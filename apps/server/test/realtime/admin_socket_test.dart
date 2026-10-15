import 'dart:convert';
import 'dart:io';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../support/realtime_support.dart';
import '../support/test_server.dart';

void main() {
  late TestServer server;
  late Map<String, String> admin;

  setUp(() async {
    server = await TestServer.start();
    admin = await setupAdmin(server);
  });

  test('sem Origin o upgrade é recusado com 403', () async {
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(server.uri(WsPaths.admin));
    request.headers
      ..set('connection', 'Upgrade')
      ..set('upgrade', 'websocket')
      ..set('sec-websocket-version', '13')
      ..set('sec-websocket-key', base64.encode(List.filled(16, 1)))
      ..set('cookie', admin['cookie']!);
    final response = await request.close();
    await response.drain<void>();

    expect(response.statusCode, 403);
  });

  test('Origin de outro site é recusado', () async {
    await expectLater(
      connectAdmin(server, admin, origin: 'http://evil.example'),
      throwsA(isA<WebSocketChannelException>()),
    );
  });

  test('Origin certo sem cookie fecha com 4401', () async {
    final inbox = Inbox(await connectAdmin(server, const {}));

    expect(await inbox.closeCode(), WsCloseCodes.unauthorized);
  });

  test('recebe os eventos de status das TVs', () async {
    final inbox = Inbox(await connectAdmin(server, admin));
    final tv = insertDevice(server);

    final channel = await connectDevice(server, tv.token);
    sendHello(channel);

    final online = await inbox.next();
    expect(online.type, MessageTypes.deviceOnline);
    expect(online.payload, {'deviceId': tv.id});
    final state = await inbox.next();
    expect(state.type, MessageTypes.deviceState);
    final summary = DeviceSummary.fromJson(state.payload);
    expect(summary.id, tv.id);
    expect(summary.online, isTrue);

    await channel.sink.close();
    final offline = await inbox.next();
    expect(offline.type, MessageTypes.deviceOffline);
    expect(offline.payload['deviceId'], tv.id);
    expect(offline.payload['lastSeenAt'], isA<String>());
  });

  test('recebe device.paired quando uma TV pareia', () async {
    final inbox = Inbox(await connectAdmin(server, admin));
    final codeResponse = await server.post(
      '/api/v1/pairing-codes',
      headers: admin,
    );
    final code = (jsonBody(codeResponse)! as Map)['code'] as String;

    final response = await server.post(
      '/api/v1/pair',
      json: PairRequest(code: code, deviceInfo: testDeviceInfo).toJson(),
    );
    final deviceId = (jsonBody(response)! as Map)['deviceId'];

    final paired = await inbox.next();
    expect(paired.type, MessageTypes.devicePaired);
    final summary = DeviceSummary.fromJson(paired.payload);
    expect(summary.id, deviceId);
    expect(summary.online, isFalse);
  });
}
