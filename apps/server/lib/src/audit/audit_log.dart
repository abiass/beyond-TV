import 'dart:io';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';

import '../auth/sessions.dart';
import '../clock.dart';
import '../logging.dart';

final _log = Logger('audit');

/// Log de auditoria na tabela `audit_log`.
///
/// Só guarda método, caminho (sem query), status, admin e IP. Linhas com mais
/// de [maxAge] ou além das [maxRows] mais recentes são apagadas a cada
/// gravação (as duas buscas usam índice, então o custo é baixo).
class AuditLog {
  AuditLog(
    this._db, {
    Clock clock = DateTime.now,
    this.maxRows = defaultMaxRows,
    this.maxAge = defaultMaxAge,
  }) : _clock = clock;

  static const defaultMaxRows = 10000;
  static const defaultMaxAge = Duration(days: 90);
  static const defaultLimit = 100;
  static const maxLimit = 500;

  final Database _db;
  final Clock _clock;
  final int maxRows;
  final Duration maxAge;

  /// Grava uma linha e aplica a retenção.
  void record({
    required String method,
    required String path,
    required int status,
    int? adminId,
    String? ip,
  }) {
    final now = _clock();
    _db.execute(
      'INSERT INTO audit_log (at, method, path, status, admin_id, ip) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [isoUtc(now), method, path, status, adminId, ip],
    );
    _db.execute('DELETE FROM audit_log WHERE at < ?', [
      isoUtc(now.subtract(maxAge)),
    ]);
    _db.execute(
      'DELETE FROM audit_log WHERE id <= '
      '(SELECT id FROM audit_log ORDER BY id DESC LIMIT 1 OFFSET ?)',
      [maxRows],
    );
  }

  /// Linhas da mais nova para a mais antiga; [before] pagina pelo `id`.
  List<AuditEntry> list({int limit = defaultLimit, int? before}) {
    final rows = _db.select(
      'SELECT l.id, l.at, l.method, l.path, l.status, l.admin_id, l.ip, '
      'a.username AS admin_name FROM audit_log l '
      'LEFT JOIN admins a ON a.id = l.admin_id '
      '${before == null ? '' : 'WHERE l.id < ? '}'
      'ORDER BY l.id DESC LIMIT ?',
      [?before, limit],
    );
    return [
      for (final row in rows)
        AuditEntry(
          id: row['id'] as int,
          at: DateTime.parse(row['at'] as String),
          method: row['method'] as String,
          path: row['path'] as String,
          status: row['status'] as int,
          adminId: row['admin_id'] as int?,
          adminName: row['admin_name'] as String?,
          ip: row['ip'] as String?,
        ),
    ];
  }
}

const _audited = {'POST', 'PUT', 'PATCH', 'DELETE'};

/// Grava no [audit] toda requisição que muda algo em `/api/v1/`.
///
/// Fica por fora do [errorHandler] para ver o status final. O admin é
/// identificado antes do handler (o logout apaga a sessão). Falha ao gravar
/// só gera um aviso no log.
Middleware auditLog(AuditLog audit, SessionStore sessions) =>
    (inner) => (request) async {
      final path = request.url.path;
      // Quadros e entradas do controle ao vivo chegam várias vezes por
      // segundo; a abertura do controle (`POST .../live`) é que fica gravada.
      if (!_audited.contains(request.method) ||
          !path.startsWith('api/v1/') ||
          path.contains('/live/')) {
        return inner(request);
      }
      int? adminId;
      try {
        final token = SessionStore.tokenOf(request);
        adminId = token == null ? null : sessions.findAdmin(token)?.id;
      } on Object {
        adminId = null;
      }
      final response = await inner(request);
      try {
        audit.record(
          method: request.method,
          path: '/$path',
          status: response.statusCode,
          adminId: adminId,
          ip: _ipOf(request),
        );
      } on Object catch (e) {
        _log.warning(
          LogEvent('falha ao gravar auditoria', {
            'method': request.method,
            'path': '/$path',
          }),
          e,
        );
      }
      return response;
    };

String? _ipOf(Request request) =>
    switch (request.context['shelf.io.connection_info']) {
      final HttpConnectionInfo info => info.remoteAddress.address,
      _ => null,
    };
