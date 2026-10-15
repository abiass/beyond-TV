import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/admins.dart';
import '../auth/passwords.dart';
import '../auth/sessions.dart';
import '../http/json.dart';

/// Rotas da configuração inicial (criação do administrador).
///
/// O `POST /api/v1/setup` só funciona enquanto não existe administrador: não
/// há senha padrão, quem abre o dashboard pela primeira vez cria a sua. O
/// administrador criado já sai com a sessão aberta.
class SetupApi {
  SetupApi({
    required AdminStore admins,
    required SessionStore sessions,
    required PasswordHasher hasher,
  }) : _admins = admins,
       _sessions = sessions,
       _hasher = hasher;

  final AdminStore _admins;
  final SessionStore _sessions;
  final PasswordHasher _hasher;

  void addRoutes(Router router) {
    router
      ..get('/api/v1/setup/status', _status)
      ..post('/api/v1/setup', _setup);
  }

  Response _status(Request request) =>
      jsonResponse({'configured': _admins.hasAdmin});

  Future<Response> _setup(Request request) async {
    if (_admins.hasAdmin) throw _alreadyConfigured;

    final body = await readJsonObject(request);
    final username = requireString(body, 'username').trim();
    final password = requireString(body, 'password');

    final error = validateUsername(username) ?? validatePassword(password);
    if (error != null) throw ApiException(400, 'invalid_credentials', error);

    final hash = await _hasher.hash(password);
    final admin = _admins.createFirst(username, hash);
    if (admin == null) throw _alreadyConfigured;

    final token = _sessions.create(admin.id);
    return jsonResponse(
      {'username': admin.username},
      status: 201,
      headers: {'set-cookie': _sessions.cookieFor(token)},
    );
  }

  static const _alreadyConfigured = ApiException.conflict(
    'already_configured',
    'O administrador já foi criado. Faça login.',
  );
}
