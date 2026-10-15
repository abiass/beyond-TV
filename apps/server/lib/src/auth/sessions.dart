import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';

import '../clock.dart';
import '../http/json.dart';
import 'admins.dart';
import 'tokens.dart';

/// Duração de uma sessão do dashboard.
const defaultSessionTtl = Duration(days: 7);

/// Nome do cookie de sessão.
const sessionCookieName = 'beyond_session';

/// Sessões do administrador, guardadas na tabela `sessions`.
///
/// O ID da sessão só existe em claro no cookie; o banco guarda o SHA-256.
class SessionStore {
  SessionStore(
    this._db, {
    Clock clock = DateTime.now,
    this.ttl = defaultSessionTtl,
  }) : _clock = clock;

  final Database _db;
  final Clock _clock;

  /// Tempo de vida de cada sessão, contado a partir do login.
  final Duration ttl;

  /// Abre uma sessão para [adminId] e devolve o token para o cookie.
  String create(int adminId) {
    final token = generateToken();
    _db.execute(
      'INSERT INTO sessions (id_hash, admin_id, expires_at) VALUES (?, ?, ?)',
      [hashToken(token), adminId, isoUtc(_clock().add(ttl))],
    );
    return token;
  }

  /// Administrador da sessão [token], ou `null` se ela não existe ou expirou.
  Admin? findAdmin(String token) {
    final rows = _db.select(
      'SELECT a.id, a.username, a.password_hash FROM sessions s '
      'JOIN admins a ON a.id = s.admin_id '
      'WHERE s.id_hash = ? AND s.expires_at > ?',
      [hashToken(token), isoUtc(_clock())],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return Admin(
      id: row['id'] as int,
      username: row['username'] as String,
      passwordHash: row['password_hash'] as String,
    );
  }

  /// Encerra a sessão [token].
  void delete(String token) =>
      _db.execute('DELETE FROM sessions WHERE id_hash = ?', [hashToken(token)]);

  /// Apaga as sessões expiradas e devolve quantas foram removidas.
  int purgeExpired() {
    _db.execute('DELETE FROM sessions WHERE expires_at <= ?', [
      isoUtc(_clock()),
    ]);
    return _db.updatedRows;
  }

  /// Valor do cabeçalho `Set-Cookie` que grava a sessão [token].
  ///
  /// `HttpOnly` impede o JavaScript de ler o cookie e `SameSite=Strict`
  /// impede outros sites de usá-lo. Não há `Secure` porque o servidor roda em
  /// HTTP na LAN (veja a seção 10 do plano).
  String cookieFor(String token) =>
      '$sessionCookieName=$token; Path=/; HttpOnly; SameSite=Strict; '
      'Max-Age=${ttl.inSeconds}';

  /// Valor do cabeçalho `Set-Cookie` que apaga o cookie de sessão.
  static const clearCookie =
      '$sessionCookieName=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0';

  /// Token de sessão enviado no cookie de [request], se houver.
  static String? tokenOf(Request request) {
    final header = request.headers['cookie'];
    if (header == null) return null;
    for (final pair in header.split(';')) {
      final index = pair.indexOf('=');
      if (index < 0) continue;
      if (pair.substring(0, index).trim() == sessionCookieName) {
        final value = pair.substring(index + 1).trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }

  /// Middleware que só deixa passar requisições com sessão válida.
  ///
  /// O administrador fica disponível para o handler em [adminOf].
  Middleware requireAdmin() =>
      (inner) => (request) {
        final token = tokenOf(request);
        final admin = token == null ? null : findAdmin(token);
        if (admin == null) throw const ApiException.unauthorized();
        return inner(request.change(context: {_adminKey: admin}));
      };

  /// Administrador autenticado pelo [requireAdmin].
  static Admin adminOf(Request request) => request.context[_adminKey]! as Admin;

  static const _adminKey = 'beyond.admin';
}
