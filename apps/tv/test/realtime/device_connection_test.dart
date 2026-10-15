import 'dart:math';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_tv/src/device/credentials.dart';
import 'package:beyond_tv/src/realtime/backoff.dart';
import 'package:beyond_tv/src/realtime/device_connection.dart';
import 'package:beyond_tv/src/server/server_address.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';
import '../support/fakes.dart';

const _credentials = Credentials(
  deviceId: 'tv-1',
  deviceToken: 'segredo',
  server: pcSala,
);

Future<void> _wait([int ms = 40]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late FakeConnector connector;
  late MemoryCredentialStore store;
  late FakeDiscovery discovery;
  late List<DeviceConnection> created;

  setUp(() {
    connector = FakeConnector();
    store = MemoryCredentialStore(_credentials);
    discovery = FakeDiscovery();
    created = [];
  });

  tearDown(() async {
    for (final c in created) {
      await c.dispose();
    }
  });

  DeviceConnection make({
    Duration heartbeatEvery = const Duration(seconds: 30),
    bool withDiscovery = false,
  }) {
    final connection = DeviceConnection(
      credentials: _credentials,
      deviceInfo: const FakeDeviceInfo(),
      store: store,
      discovery: withDiscovery ? discovery : null,
      connector: connector.call,
      backoff: Backoff(
        initial: const Duration(milliseconds: 10),
        max: const Duration(milliseconds: 20),
        random: Random(1),
      ),
      heartbeatEvery: heartbeatEvery,
    );
    created.add(connection);
    return connection;
  }

  test('envia hello primeiro, com o token só no header', () async {
    final connection = make()..start();
    await _wait();

    expect(connection.status, ConnectionStatus.online);
    expect(
      connector.uris.single.toString(),
      'ws://192.168.0.10:8787/ws/device',
    );
    expect(connector.uris.single.toString(), isNot(contains('segredo')));
    expect(connector.headers.single['authorization'], 'Bearer segredo');

    final first = connector.last.envelopes.first;
    expect(first.type, MessageTypes.hello);
    final hello = HelloPayload.fromJson(first.payload);
    expect(hello.deviceInfo.model, 'X1');
  });

  test('manda heartbeats no intervalo', () async {
    make(heartbeatEvery: const Duration(milliseconds: 50)).start();
    await _wait(180);

    final types = connector.last.envelopes.map((e) => e.type).toList();
    expect(types.first, MessageTypes.hello);
    expect(
      types.where((t) => t == MessageTypes.heartbeat).length,
      greaterThanOrEqualTo(2),
    );
  });

  test('4401 apaga credenciais e não reconecta', () async {
    final connection = make()..start();
    await _wait();
    connector.last.serverClose(WsCloseCodes.unauthorized);
    await _wait(100);

    expect(connection.status, ConnectionStatus.unauthorized);
    expect(store.saved, isNull);
    expect(connector.uris, hasLength(1));
  });

  test('4409 vira replaced e não reconecta', () async {
    final connection = make()..start();
    await _wait();
    connector.last.serverClose(WsCloseCodes.replaced);
    await _wait(100);

    expect(connection.status, ConnectionStatus.replaced);
    expect(connector.uris, hasLength(1));
  });

  test('4426 vira outdated e não reconecta logo', () async {
    final connection = make()..start();
    await _wait();
    connector.last.serverClose(WsCloseCodes.incompatibleVersion);
    await _wait(100);

    expect(connection.status, ConnectionStatus.outdated);
    expect(connector.uris, hasLength(1));
  });

  test('erro de conexão reconecta depois do backoff', () async {
    connector.failures = 1;
    final connection = make()..start();
    await _wait(5);

    expect(connection.status, ConnectionStatus.offline);
    expect(connection.nextRetryIn, isNotNull);

    await _wait(80);
    expect(connector.uris, hasLength(2));
    expect(connection.status, ConnectionStatus.online);
  });

  test('queda comum (1006) reconecta', () async {
    make().start();
    await _wait();
    connector.last.serverClose(1006);
    await _wait(80);

    expect(connector.uris, hasLength(2));
  });

  test('3 falhas e mesmo serverId em outro host: atualiza e reconecta',
      () async {
    connector.failures = 3;
    discovery.servers = [
      const ServerAddress(
        host: '192.168.0.50',
        name: 'PC-SALA',
        serverId: 'abc',
      ),
    ];
    final connection = make(withDiscovery: true)..start();
    await _wait(200);

    expect(discovery.calls, 1);
    expect(store.saved!.server.host, '192.168.0.50');
    expect(store.saved!.deviceToken, 'segredo');
    expect(connection.credentials.server.host, '192.168.0.50');
    expect(connector.uris.last.host, '192.168.0.50');
    expect(connection.status, ConnectionStatus.online);
  });

  test('descoberta com outro serverId é ignorada', () async {
    connector.failures = 3;
    discovery.servers = [
      const ServerAddress(host: '192.168.0.50', name: 'OUTRO', serverId: 'xyz'),
    ];
    final connection = make(withDiscovery: true)..start();
    await _wait(200);

    expect(discovery.calls, 1);
    expect(store.saved!.server.host, '192.168.0.10');
    expect(connection.credentials.server.host, '192.168.0.10');
    expect(connector.uris.every((u) => u.host == '192.168.0.10'), isTrue);
  });

  test('mensagens recebidas chegam em messages; lixo é ignorado', () async {
    final connection = make()..start();
    final received = <String>[];
    connection.messages.listen((e) => received.add(e.type));
    await _wait();

    connector.last
      ..serverSendRaw('não é json')
      ..serverSend(Envelope.create('algo.novo'));
    await _wait();

    expect(received, ['algo.novo']);
  });
}
