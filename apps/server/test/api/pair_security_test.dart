import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_server/server.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/test_server.dart';

/// Regras de segurança do pareamento: validade, uso único e rate limit.
void main() {
  late FakeClock clock;
  late TestServer server;
  late Map<String, String> admin;

  setUp(() async {
    clock = FakeClock();
    server = await TestServer.start(clock: clock.call);
    final setup = await server.post(
      '/api/v1/setup',
      json: {'username': 'admin', 'password': 'senha-forte-1'},
    );
    admin = sessionHeader(sessionTokenFrom(setup)!);
  });

  Future<String> createCode() async {
    final response = await server.post('/api/v1/pairing-codes', headers: admin);
    return (jsonBody(response)! as Map)['code'] as String;
  }

  Future<http.Response> pair(String code) => server.post(
    '/api/v1/pair',
    json: PairRequest(
      code: code,
      deviceInfo: const DeviceInfo(appVersion: '0.1.0'),
    ).toJson(),
  );

  int deviceCount() => server.db.select('SELECT * FROM devices').length;

  group('código expirado', () {
    test('é recusado depois de 10 minutos', () async {
      final code = await createCode();
      clock.advance(pairingCodeTtl);

      final response = await pair(code);

      expect(response.statusCode, 400);
      expect(errorCode(response), 'expired_code');
      expect(deviceCount(), 0);
    });

    test('ainda vale no último segundo', () async {
      final code = await createCode();
      clock.advance(pairingCodeTtl - const Duration(seconds: 1));

      expect((await pair(code)).statusCode, 201);
    });

    test('vira inválido depois de esquecido', () async {
      final code = await createCode();
      clock.advance(pairingCodeTtl * 2 + const Duration(seconds: 1));

      final response = await pair(code);

      expect(errorCode(response), 'invalid_code');
    });
  });

  group('código reutilizado', () {
    test('a segunda TV recebe código inválido', () async {
      final code = await createCode();

      expect((await pair(code)).statusCode, 201);
      final second = await pair(code);

      expect(second.statusCode, 400);
      expect(errorCode(second), 'invalid_code');
      expect(deviceCount(), 1);
    });

    test('pedidos simultâneos com o mesmo código pareiam uma TV só', () async {
      final code = await createCode();

      final responses = await Future.wait([
        for (var i = 0; i < 3; i++) pair(code),
      ]);

      expect(responses.where((r) => r.statusCode == 201), hasLength(1));
      expect(deviceCount(), 1);
    });

    test('cada código gera uma TV com token próprio', () async {
      final first = PairResponse.fromJson(
        jsonBody(await pair(await createCode()))! as Map<String, Object?>,
      );
      final second = PairResponse.fromJson(
        jsonBody(await pair(await createCode()))! as Map<String, Object?>,
      );

      expect(first.deviceId, isNot(second.deviceId));
      expect(first.deviceToken, isNot(second.deviceToken));
      expect(deviceCount(), 2);
    });
  });

  group('rate limit', () {
    test(
      'bloqueia o IP na 6ª tentativa do minuto, mesmo com código certo',
      () async {
        for (var i = 0; i < PairingApi.maxPairAttempts; i++) {
          expect(errorCode(await pair('ZZZZZZ')), 'invalid_code');
        }

        final blocked = await pair(await createCode());

        expect(blocked.statusCode, 429);
        expect(errorCode(blocked), 'too_many_requests');
        expect(blocked.headers['retry-after'], isNotNull);
        expect(deviceCount(), 0);
      },
    );

    test('libera de novo quando a janela passa', () async {
      for (var i = 0; i < PairingApi.maxPairAttempts; i++) {
        await pair('ZZZZZZ');
      }
      final code = await createCode();
      expect((await pair(code)).statusCode, 429);

      clock.advance(const Duration(minutes: 1));

      expect((await pair(code)).statusCode, 201);
    });

    test('o bloqueio não consome o código', () async {
      final code = await createCode();
      for (var i = 0; i < PairingApi.maxPairAttempts; i++) {
        await pair('ZZZZZZ');
      }
      await pair(code);

      final status = await server.get(
        '/api/v1/pairing-codes/$code',
        headers: admin,
      );
      expect((jsonBody(status)! as Map)['status'], 'pending');
    });
  });
}
