import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_server/server.dart';
import 'package:test/test.dart';

import '../support/test_server.dart';

class FakeConnection implements DeviceConnection {
  final sent = <Envelope>[];
  int? closedWith;

  @override
  void send(Envelope envelope) => sent.add(envelope);

  @override
  Future<void> close(int code, String reason) async => closedWith = code;
}

void main() {
  late FakeClock clock;
  late DeviceStore devices;
  late DeviceHub hub;
  late String id;
  late List<Envelope> events;

  setUp(() {
    clock = FakeClock();
    final db = openDatabase();
    addTearDown(db.close);
    devices = DeviceStore(db, clock: clock.call);
    hub = DeviceHub(
      devices: devices,
      media: MediaStore(db, clock: clock.call),
      playlists: PlaylistStore(db, MediaStore(db, clock: clock.call)),
      clock: clock.call,
    );
    id = generateId();
    devices.create(
      id: id,
      name: 'TV',
      tokenHash: hashToken('x'),
      info: const DeviceInfo(appVersion: '0.5.0'),
    );
    events = [];
    hub.events.listen(events.add);
  });

  List<String> types() => events.map((e) => e.type).toList();

  test('um segundo attach fecha a conexão anterior com 4409', () {
    final first = FakeConnection();
    final second = FakeConnection();

    hub.attach(id, first);
    hub.attach(id, second);

    expect(first.closedWith, WsCloseCodes.replaced);
    expect(second.closedWith, isNull);
    expect(hub.isOnline(id), isTrue);
  });

  test('detach de conexão antiga não marca a TV como offline', () async {
    final first = FakeConnection();
    final second = FakeConnection();
    hub.attach(id, first);
    hub.attach(id, second);

    hub.detach(id, first);
    await Future<void>.delayed(Duration.zero);

    expect(hub.isOnline(id), isTrue);
    expect(types(), isEmpty);

    hub.detach(id, second);
    await Future<void>.delayed(Duration.zero);

    expect(hub.isOnline(id), isFalse);
    expect(types(), [MessageTypes.deviceOffline]);
    expect(events.single.payload['deviceId'], id);
  });

  test('grava last_seen_at no máximo uma vez por minuto', () {
    hub.attach(id, FakeConnection());
    final start = clock.now;

    hub.markSeen(id);
    expect(devices.find(id)!.lastSeenAt, start);

    clock.advance(const Duration(seconds: 30));
    hub.markSeen(id);
    expect(devices.find(id)!.lastSeenAt, start);

    clock.advance(const Duration(seconds: 30));
    hub.markSeen(id);
    expect(devices.find(id)!.lastSeenAt, clock.now);
  });

  test('mudar o currentItem publica device.state', () async {
    hub.attach(id, FakeConnection());

    hub.markSeen(id, currentItem: 'https://a.example');
    hub.markSeen(id, currentItem: 'https://a.example');
    hub.markSeen(id, currentItem: 'https://b.example');
    await Future<void>.delayed(Duration.zero);

    expect(types(), [MessageTypes.deviceState, MessageTypes.deviceState]);
    expect(events.last.payload['currentItem'], 'https://b.example');
    expect(hub.currentItemOf(id), 'https://b.example');
  });

  test('disconnect fecha a TV sem publicar device.offline', () async {
    final conn = FakeConnection();
    hub.attach(id, conn);

    hub.disconnect(id, WsCloseCodes.unauthorized);
    hub.detach(id, conn);
    await Future<void>.delayed(Duration.zero);

    expect(conn.closedWith, WsCloseCodes.unauthorized);
    expect(hub.isOnline(id), isFalse);
    expect(types(), isEmpty);
  });
}
