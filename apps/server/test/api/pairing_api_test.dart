import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:test/test.dart';

import '../support/test_server.dart';

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

  Future<PairingCode> createCode() async {
    final response = await server.post('/api/v1/pairing-codes', headers: admin);
    expect(response.statusCode, 201);
    return PairingCode.fromJson(jsonBody(response)! as Map<String, Object?>);
  }

  test('gera um código válido por 10 minutos', () async {
    final code = await createCode();

    expect(isWellFormedPairingCode(code.code), isTrue);
    expect(code.expiresAt, clock.now.add(pairingCodeTtl));
  });

  test('consulta a situação do código', () async {
    final code = await createCode();

    final pending = await server.get(
      '/api/v1/pairing-codes/${code.code}',
      headers: admin,
    );
    expect(jsonBody(pending), {
      'code': code.code,
      'expiresAt': code.expiresAt.toIso8601String(),
      'status': 'pending',
    });

    clock.advance(pairingCodeTtl);
    final expired = await server.get(
      '/api/v1/pairing-codes/${code.code}',
      headers: admin,
    );
    expect((jsonBody(expired)! as Map)['status'], 'expired');
  });

  test('código desconhecido responde 404', () async {
    final response = await server.get(
      '/api/v1/pairing-codes/ZZZZZZ',
      headers: admin,
    );

    expect(response.statusCode, 404);
  });

  test('exige sessão de administrador', () async {
    final create = await server.post('/api/v1/pairing-codes');
    final status = await server.get('/api/v1/pairing-codes/ZZZZZZ');

    expect(create.statusCode, 401);
    expect(status.statusCode, 401);
  });
}
