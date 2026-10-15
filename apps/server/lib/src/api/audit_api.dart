import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../audit/audit_log.dart';
import '../auth/sessions.dart';
import '../http/json.dart';

/// `GET /api/v1/audit?limit=&before=` (admin): log de auditoria, da linha
/// mais nova para a mais antiga.
class AuditApi {
  AuditApi({required SessionStore sessions, required AuditLog audit})
    : _sessions = sessions,
      _audit = audit;

  final SessionStore _sessions;
  final AuditLog _audit;

  void addRoutes(Router router) {
    final admin = const Pipeline().addMiddleware(_sessions.requireAdmin());
    router.get('/api/v1/audit', admin.addHandler(_list));
  }

  Response _list(Request request) {
    final query = request.url.queryParameters;
    final limit = _intParam(
      query['limit'],
      'limit',
      fallback: AuditLog.defaultLimit,
    );
    if (limit < 1 || limit > AuditLog.maxLimit) {
      throw const ApiException.badRequest(
        'Parâmetro "limit" deve ficar entre 1 e ${AuditLog.maxLimit}.',
      );
    }
    final before = query.containsKey('before')
        ? _intParam(query['before'], 'before', fallback: 0)
        : null;
    return jsonResponse({
      'entries': [
        for (final e in _audit.list(limit: limit, before: before)) e.toJson(),
      ],
    });
  }

  static int _intParam(String? raw, String name, {required int fallback}) {
    if (raw == null) return fallback;
    return int.tryParse(raw) ??
        (throw ApiException.badRequest('Parâmetro "$name" inválido.'));
  }
}
