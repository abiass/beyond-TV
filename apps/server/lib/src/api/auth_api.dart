import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/admins.dart';
import '../auth/passwords.dart';
import '../auth/sessions.dart';
import '../http/json.dart';
import '../http/rate_limit.dart';

/// Login, logout e consulta da sessão do administrador.
///
/// Cada IP pode errar o login [maxFailedLogins] vezes por minuto; depois
/// disso recebe `429` até a janela passar.
class AuthApi {
  AuthApi({
    required AdminStore admins,
    required SessionStore sessions,
    required PasswordHasher hasher,
    RateLimiter? loginLimiter,
  }) : _admins = admins,
       _sessions = sessions,
       _hasher = hasher,
       _loginLimiter =
           loginLimiter ??
           RateLimiter(
             maxAttempts: maxFailedLogins,
             window: const Duration(minutes: 1),
           );

  static const maxFailedLogins = 5;

  final AdminStore _admins;
  final SessionStore _sessions;
  final PasswordHasher _hasher;
  final RateLimiter _loginLimiter;

  /// Hash usado quando o usuário não existe, para a resposta demorar o mesmo
  /// tempo e não revelar quais usuários existem.
  late final Future<String> _dummyHash = _hasher.hash('usuario-inexistente');

  void addRoutes(Router router) {
    router
      ..post('/api/v1/auth/login', _login)
      ..post('/api/v1/auth/logout', _logout)
      ..get(
        '/api/v1/auth/session',
        const Pipeline()
            .addMiddleware(_sessions.requireAdmin())
            .addHandler(_session),
      );
  }

  Future<Response> _login(Request request) async {
    final body = await readJsonObject(request);
    final username = requireString(body, 'username').trim();
    final password = requireString(body, 'password');

    final ip = clientIp(request);
    _loginLimiter.check(ip);

    final admin = _admins.findByUsername(username);
    final valid = await _hasher.verify(
      password,
      admin?.passwordHash ?? await _dummyHash,
    );
    if (admin == null || !valid) {
      _loginLimiter.hit(ip);
      throw invalidLogin;
    }
    _loginLimiter.reset(ip);

    _sessions.purgeExpired();
    final token = _sessions.create(admin.id);
    return jsonResponse(
      {'username': admin.username},
      headers: {'set-cookie': _sessions.cookieFor(token)},
    );
  }

  Response _logout(Request request) {
    final token = SessionStore.tokenOf(request);
    if (token != null) _sessions.delete(token);
    return Response(204, headers: {'set-cookie': SessionStore.clearCookie});
  }

  Response _session(Request request) =>
      jsonResponse({'username': SessionStore.adminOf(request).username});

  /// Erro de login, igual para usuário inexistente e senha errada.
  static const invalidLogin = ApiException(
    401,
    'invalid_login',
    'Usuário ou senha incorretos.',
  );
}
