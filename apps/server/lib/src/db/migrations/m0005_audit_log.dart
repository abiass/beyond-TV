import '../migrator.dart';

/// Log de auditoria das ações que mudam algo na API.
///
/// Guarda só método, caminho (sem query), status, admin e IP; nunca corpo,
/// cookies ou cabeçalhos. `admin_id` vira `NULL` se o admin for apagado.
const migration0005 = Migration(5, 'audit_log', r'''
CREATE TABLE audit_log (
  id       INTEGER PRIMARY KEY,
  at       TEXT NOT NULL,
  method   TEXT NOT NULL,
  path     TEXT NOT NULL,
  status   INTEGER NOT NULL,
  admin_id INTEGER REFERENCES admins (id) ON DELETE SET NULL,
  ip       TEXT
) STRICT;

CREATE INDEX audit_log_at ON audit_log (at);
''');
