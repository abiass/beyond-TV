import 'package:beyond_server/server.dart';
import 'package:test/test.dart';

import '../support/test_server.dart';

void main() {
  late TestServer server;
  late String setupToken;

  setUp(() async {
    server = await TestServer.start();
    final response = await server.post(
      '/api/v1/setup',
      json: {'username': 'admin', 'password': 'senha-forte-1'},
    );
    setupToken = sessionTokenFrom(response)!;
  });

  Future<String> login() async {
    final response = await server.post(
      '/api/v1/auth/login',
      json: {'username': 'admin', 'password': 'senha-forte-1'},
    );
    expect(response.statusCode, 200);
    return sessionTokenFrom(response)!;
  }

  test('o setup já abre a sessão do administrador criado', () async {
    final response = await server.get(
      '/api/v1/auth/session',
      headers: sessionHeader(setupToken),
    );

    expect(response.statusCode, 200);
    expect(jsonBody(response), {'username': 'admin'});
  });

  test('login grava cookie HttpOnly e SameSite=Strict', () async {
    final response = await server.post(
      '/api/v1/auth/login',
      json: {'username': 'ADMIN', 'password': 'senha-forte-1'},
    );

    expect(response.statusCode, 200);
    expect(jsonBody(response), {'username': 'admin'});
    final cookie = response.headers['set-cookie']!;
    expect(cookie, contains('HttpOnly'));
    expect(cookie, contains('SameSite=Strict'));
    expect(cookie, contains('Path=/'));
    expect(cookie, contains('Max-Age=${defaultSessionTtl.inSeconds}'));
  });

  test('o banco guarda só o hash do token da sessão', () async {
    final token = await login();

    final hashes = server.db
        .select('SELECT id_hash FROM sessions')
        .map((row) => row['id_hash'])
        .toList();
    expect(hashes, contains(hashToken(token)));
    expect(hashes, isNot(contains(token)));
  });

  for (final (description, username, password) in [
    ('senha errada', 'admin', 'senha-errada'),
    ('usuário inexistente', 'fulano', 'senha-forte-1'),
  ]) {
    test('$description responde 401 sem abrir sessão', () async {
      final response = await server.post(
        '/api/v1/auth/login',
        json: {'username': username, 'password': password},
      );

      expect(response.statusCode, 401);
      expect(errorCode(response), 'invalid_login');
      expect(response.headers['set-cookie'], isNull);
    });
  }

  test('sem cookie ou com cookie inválido a sessão responde 401', () async {
    final withoutCookie = await server.get('/api/v1/auth/session');
    final withInvalid = await server.get(
      '/api/v1/auth/session',
      headers: sessionHeader('inventado'),
    );

    expect(withoutCookie.statusCode, 401);
    expect(errorCode(withoutCookie), 'unauthorized');
    expect(withInvalid.statusCode, 401);
  });

  test('logout encerra a sessão e apaga o cookie', () async {
    final token = await login();

    final response = await server.post(
      '/api/v1/auth/logout',
      headers: sessionHeader(token),
    );

    expect(response.statusCode, 204);
    expect(response.headers['set-cookie'], contains('Max-Age=0'));
    final after = await server.get(
      '/api/v1/auth/session',
      headers: sessionHeader(token),
    );
    expect(after.statusCode, 401);

    // As outras sessões continuam valendo.
    final other = await server.get(
      '/api/v1/auth/session',
      headers: sessionHeader(setupToken),
    );
    expect(other.statusCode, 200);
  });

  test('lê o cookie de sessão no meio de outros cookies', () async {
    final token = await login();

    final response = await server.get(
      '/api/v1/auth/session',
      headers: {'cookie': 'tema=escuro; $sessionCookieName=$token; x=1'},
    );

    expect(response.statusCode, 200);
  });

  Future<int> attemptLogin(String password) async => (await server.post(
    '/api/v1/auth/login',
    json: {'username': 'admin', 'password': password},
  )).statusCode;

  test('bloqueia o IP após 5 logins errados por minuto', () async {
    for (var i = 0; i < AuthApi.maxFailedLogins; i++) {
      expect(await attemptLogin('senha-errada'), 401);
    }

    final blocked = await server.post(
      '/api/v1/auth/login',
      json: {'username': 'admin', 'password': 'senha-forte-1'},
    );
    expect(blocked.statusCode, 429);
    expect(errorCode(blocked), 'too_many_requests');
    expect(int.parse(blocked.headers['retry-after']!), inInclusiveRange(1, 60));
  });

  test('login certo zera o contador de erros', () async {
    for (var i = 0; i < AuthApi.maxFailedLogins - 1; i++) {
      await attemptLogin('senha-errada');
    }
    await login();

    expect(await attemptLogin('senha-errada'), 401);
    expect(await attemptLogin('senha-errada'), 401);
  });

  test('recusa login vindo de outra origem', () async {
    final response = await server.post(
      '/api/v1/auth/login',
      headers: {'origin': 'http://evil.example'},
      json: {'username': 'admin', 'password': 'senha-forte-1'},
    );

    expect(response.statusCode, 403);
    expect(response.headers['set-cookie'], isNull);
  });
}
