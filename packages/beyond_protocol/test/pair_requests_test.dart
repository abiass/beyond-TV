import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:test/test.dart';

void main() {
  final expiresAt = DateTime.utc(2026, 10, 16, 12, 10);

  test('PairRequestTicket ida e volta', () {
    final ticket = PairRequestTicket(
      id: 'r1',
      secret: 's3cr3t',
      confirmCode: '4821',
      expiresAt: expiresAt,
    );

    final back = PairRequestTicket.fromJson(ticket.toJson());

    expect(back.id, 'r1');
    expect(back.secret, 's3cr3t');
    expect(back.confirmCode, '4821');
    expect(back.expiresAt, expiresAt);
  });

  group('PairRequestPoll', () {
    test('pendente não traz credenciais', () {
      final poll = PairRequestPoll.fromJson({'status': 'pending'});

      expect(poll.status, PairRequestStatus.pending);
      expect(poll.credentials, isNull);
      expect(poll.toJson(), {'status': 'pending'});
    });

    test('aprovado traz as credenciais no mesmo objeto', () {
      const credentials = PairResponse(
        deviceId: 'tv1',
        deviceToken: 'token',
        serverId: 'abc',
      );
      final json = const PairRequestPoll(
        PairRequestStatus.approved,
        credentials: credentials,
      ).toJson();

      expect(json, {
        'status': 'approved',
        'deviceId': 'tv1',
        'deviceToken': 'token',
        'serverId': 'abc',
      });
      final back = PairRequestPoll.fromJson(json);
      expect(back.credentials?.deviceToken, 'token');
    });

    test('aprovado sem credenciais é inválido', () {
      expect(
        () => PairRequestPoll.fromJson({'status': 'approved'}),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('status desconhecido é inválido', () {
      expect(
        () => PairRequestPoll.fromJson({'status': 'talvez'}),
        throwsA(isA<ProtocolException>()),
      );
    });
  });

  test('PendingPairRequest ida e volta', () {
    final pending = PendingPairRequest(
      id: 'r1',
      confirmCode: '0042',
      deviceInfo: const DeviceInfo(appVersion: '1.1.0', model: 'X1'),
      ip: '192.168.0.42',
      createdAt: DateTime.utc(2026, 10, 16, 12),
      expiresAt: expiresAt,
    );

    final back = PendingPairRequest.fromJson(pending.toJson());

    expect(back.confirmCode, '0042');
    expect(back.deviceInfo.model, 'X1');
    expect(back.ip, '192.168.0.42');
    expect(back.createdAt, DateTime.utc(2026, 10, 16, 12));
  });
}
