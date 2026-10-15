import 'dart:convert';
import 'dart:isolate';

import 'package:bcrypt/bcrypt.dart';

/// Custo padrão do bcrypt (2^12 rodadas, por volta de 0,3 s por hash).
const defaultBcryptCost = 12;

/// Gera e confere hashes de senha com bcrypt.
///
/// O cálculo roda num isolate separado para não travar as outras requisições
/// nem os WebSockets enquanto o hash é calculado.
class PasswordHasher {
  const PasswordHasher({this.cost = defaultBcryptCost});

  /// Log2 do número de rodadas. Os testes usam o mínimo (4) para ganhar tempo.
  final int cost;

  Future<String> hash(String password) {
    final cost = this.cost;
    return Isolate.run(
      () => BCrypt.hashpw(password, BCrypt.gensalt(logRounds: cost)),
    );
  }

  Future<bool> verify(String password, String hash) {
    // O bcrypt só considera 72 bytes e o pacote lança erro acima disso.
    if (utf8.encode(password).length > maxPasswordBytes) {
      return Future.value(false);
    }
    return Isolate.run(() => BCrypt.checkpw(password, hash));
  }
}

/// Limite do bcrypt: bytes além disso seriam ignorados.
const maxPasswordBytes = 72;

/// Tamanho mínimo da senha do administrador.
const minPasswordLength = 8;

final _usernamePattern = RegExp(r'^[A-Za-z0-9._-]{3,32}$');

/// Valida o nome de usuário e devolve a mensagem de erro, ou `null` se ok.
String? validateUsername(String username) => _usernamePattern.hasMatch(username)
    ? null
    : 'O usuário deve ter de 3 a 32 caracteres: letras sem acento, números, '
          'ponto, hífen ou sublinhado.';

/// Valida a senha e devolve a mensagem de erro, ou `null` se ok.
String? validatePassword(String password) {
  if (password.length < minPasswordLength) {
    return 'A senha deve ter pelo menos $minPasswordLength caracteres.';
  }
  if (utf8.encode(password).length > maxPasswordBytes) {
    return 'A senha deve ter no máximo $maxPasswordBytes bytes.';
  }
  return null;
}
