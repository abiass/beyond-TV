import 'package:beyond_server/server.dart';
import 'package:test/test.dart';

import '../support/test_server.dart';

/// Fluxos completos de autenticação, de ponta a ponta pelo HTTP.
void main() {
  late FakeClock clock;
  late TestServer server;

  setUp(() async {
    clock = FakeClock();
    server = await TestServer.start(clock: clock.call);
  });

  Future<int> sessionStatus(String token) async => (await server.get(
    '/api/v1/auth/session',
    headers: sessionHeader(token),
  )).statusCode;

  Future<String> login() async {
    final response = await server.post(
      '/api/v1/auth/login',
      json: {'username': 'admin', 'password': 'senha-forte-1'},
    );
    expect(response.statusCode, 200);
    return sessionTokenFrom(response)!;
  }

  test('setup → logout → login → sessão', () async {
    final status = await server.get('/api/v1/setup/status');
    expect(jsonBody(status), {'configured': false});

    final setup = await server.post(
      '/api/v1/setup',
      json: {'username': 'admin', 'password': 'senha-forte-1'},
    );
    final setupToken = sessionTokenFrom(setup)!;
    expect(await sessionStatus(setupToken), 200);

    await server.post(
      '/api/v1/auth/logout',
      headers: sessionHeader(setupToken),
    );
    expect(await sessionStatus(setupToken), 401);

    final token = await login();
    expect(await sessionStatus(token), 200);
    expect(token, isNot(setupToken));
  });

  group('sessão expirada', () {
    late String token;

    setUp(() async {
      await server.post(
        '/api/v1/setup',
        json: {'username': 'admin', 'password': 'senha-forte-1'},
      );
      token = await login();
    });

    test('vale até o último instante dos 7 dias', () async {
      clock.advance(defaultSessionTtl - const Duration(milliseconds: 1));

      expect(await sessionStatus(token), 200);
    });

    test('responde 401 depois de 7 dias', () async {
      clock.advance(defaultSessionTtl);

      final response = await server.get(
        '/api/v1/auth/session',
        headers: sessionHeader(token),
      );
      expect(response.statusCode, 401);
      expect(errorCode(response), 'unauthorized');
    });

    test('é apagada do banco no próximo login', () async {
      clock.advance(defaultSessionTtl + const Duration(minutes: 1));

      final fresh = await login();

      final hashes = server.db
          .select('SELECT id_hash FROM sessions')
          .map((row) => row['id_hash']);
      expect(hashes, [hashToken(fresh)]);
    });
  });

  test('o bloqueio de login termina quando a janela passa', () async {
    await server.post(
      '/api/v1/setup',
      json: {'username': 'admin', 'password': 'senha-forte-1'},
    );
    for (var i = 0; i < AuthApi.maxFailedLogins; i++) {
      await server.post(
        '/api/v1/auth/login',
        json: {'username': 'admin', 'password': 'senha-errada'},
      );
    }
    final blocked = await server.post(
      '/api/v1/auth/login',
      json: {'username': 'admin', 'password': 'senha-forte-1'},
    );
    expect(blocked.statusCode, 429);

    clock.advance(const Duration(minutes: 1));

    await login();
  });

  test('remover o administrador derruba as sessões dele', () async {
    await server.post(
      '/api/v1/setup',
      json: {'username': 'admin', 'password': 'senha-forte-1'},
    );
    final token = await login();

    server.db.execute('DELETE FROM admins');

    expect(await sessionStatus(token), 401);
  });
}
