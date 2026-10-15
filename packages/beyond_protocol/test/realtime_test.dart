import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('HelloPayload faz ida e volta por JSON', () {
    const hello = HelloPayload(
      deviceInfo: DeviceInfo(appVersion: '0.5.0', model: 'X1'),
      currentItem: 'https://example.local/painel',
    );

    final decoded = HelloPayload.fromJson(hello.toJson());

    expect(decoded.deviceInfo, hello.deviceInfo);
    expect(decoded.currentItem, hello.currentItem);
  });

  test('HelloPayload sem deviceInfo lança ProtocolException', () {
    expect(
      () => HelloPayload.fromJson(const {}),
      throwsA(isA<ProtocolException>()),
    );
  });

  test('HeartbeatPayload faz ida e volta por JSON', () {
    const beat = HeartbeatPayload(uptimeSeconds: 42);

    expect(HeartbeatPayload.fromJson(beat.toJson()).uptimeSeconds, 42);
    expect(beat.toJson(), {'uptimeSeconds': 42});
  });

  group('DeviceSummary', () {
    final full = DeviceSummary(
      id: 'abc',
      name: 'Recepção',
      online: true,
      createdAt: DateTime.utc(2026, 10, 14, 12),
      info: const DeviceInfo(appVersion: '0.5.0', manufacturer: 'Acme'),
      groupId: 2,
      lastSeenAt: DateTime.utc(2026, 10, 14, 12, 5),
      currentItem: 'https://example.local',
    );

    test('faz ida e volta por JSON', () {
      expect(DeviceSummary.fromJson(full.toJson()).toJson(), full.toJson());
    });

    test('aceita TV que nunca conectou (info vazio, sem lastSeenAt)', () {
      final decoded = DeviceSummary.fromJson({
        'id': 'abc',
        'name': 'Nova TV',
        'online': false,
        'createdAt': '2026-10-14T12:00:00.000Z',
        'info': <String, Object?>{},
        'groupId': null,
        'lastSeenAt': null,
      });

      expect(decoded.info, isNull);
      expect(decoded.lastSeenAt, isNull);
      expect(decoded.online, isFalse);
    });

    test('copyWith troca só o que foi pedido', () {
      final offline = full.copyWith(online: false);

      expect(offline.online, isFalse);
      expect(offline.name, 'Recepção');
      expect(offline.currentItem, full.currentItem);
    });
  });
}
