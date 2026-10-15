import 'package:beyond_protocol/beyond_protocol.dart';

import '../http/json.dart';

/// Valida o endereço de um site e devolve a URL sem espaços nas pontas.
String validateUrl(Object? value) {
  final trimmed = value is String ? value.trim() : null;
  if (trimmed == null || !isSafeContentUrl(trimmed)) {
    throw const ApiException(
      400,
      'invalid_url',
      'Endereço inválido. Use um link http:// ou https://.',
    );
  }
  return trimmed;
}

/// Valida o nome de uma mídia (1 a 64 caracteres) e devolve o texto aparado.
String validateMediaName(Object? value) {
  final trimmed = value is String ? value.trim() : '';
  if (trimmed.runes.isEmpty || trimmed.runes.length > 64) {
    throw const ApiException.badRequest(
      'O nome deve ter de 1 a 64 caracteres.',
    );
  }
  return trimmed;
}
