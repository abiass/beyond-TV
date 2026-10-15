import 'package:sqlite3/sqlite3.dart';

/// Administrador cadastrado.
class Admin {
  const Admin({
    required this.id,
    required this.username,
    required this.passwordHash,
  });

  final int id;
  final String username;
  final String passwordHash;
}

/// Acesso à tabela `admins`.
class AdminStore {
  AdminStore(this._db);

  final Database _db;

  /// Indica se a configuração inicial já criou um administrador.
  bool get hasAdmin => _db.select('SELECT 1 FROM admins LIMIT 1').isNotEmpty;

  /// Cria o primeiro administrador.
  ///
  /// Retorna `null` sem gravar nada se já existir algum administrador. A
  /// checagem e a inserção são um único comando, então duas requisições de
  /// setup simultâneas não criam dois administradores.
  Admin? createFirst(String username, String passwordHash) {
    _db.execute(
      'INSERT INTO admins (username, password_hash) '
      'SELECT ?, ? WHERE NOT EXISTS (SELECT 1 FROM admins)',
      [username, passwordHash],
    );
    if (_db.updatedRows == 0) return null;
    return Admin(
      id: _db.lastInsertRowId,
      username: username,
      passwordHash: passwordHash,
    );
  }

  Admin? findByUsername(String username) => _first(
    _db.select(
      'SELECT id, username, password_hash FROM admins WHERE username = ?',
      [username],
    ),
  );

  static Admin? _first(ResultSet rows) => rows.isEmpty
      ? null
      : Admin(
          id: rows.first['id'] as int,
          username: rows.first['username'] as String,
          passwordHash: rows.first['password_hash'] as String,
        );
}
