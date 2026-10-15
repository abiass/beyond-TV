import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Tamanho máximo do corpo JSON aceito pela API.
const maxJsonBodyBytes = 64 * 1024;

/// Resposta HTTP com corpo JSON.
Response jsonResponse(
  Object? body, {
  int status = 200,
  Map<String, String> headers = const {},
}) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json; charset=utf-8', ...headers},
);

/// Lê o corpo de [request] como um objeto JSON.
///
/// Lança [ApiException] (`400`) se o corpo não for um objeto JSON e (`413`)
/// se passar de [maxBytes].
Future<Map<String, Object?>> readJsonObject(
  Request request, {
  int maxBytes = maxJsonBodyBytes,
}) async {
  final length = request.contentLength;
  if (length != null && length > maxBytes) throw const _BodyTooLarge();

  final bytes = <int>[];
  await for (final chunk in request.read()) {
    bytes.addAll(chunk);
    if (bytes.length > maxBytes) throw const _BodyTooLarge();
  }

  final Object? json;
  try {
    json = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw const ApiException.badRequest('O corpo deve ser um JSON válido.');
  }
  if (json is! Map<String, Object?>) {
    throw const ApiException.badRequest('O corpo deve ser um objeto JSON.');
  }
  return json;
}

/// Lê o campo de texto [name] de [json] ou lança [ApiException] (`400`).
String requireString(Map<String, Object?> json, String name) {
  final value = json[name];
  if (value is! String) {
    throw ApiException.badRequest('Campo "$name" ausente ou inválido.');
  }
  return value;
}

/// Erro que a API devolve ao cliente como
/// `{"error": {"code": ..., "message": ...}}`.
///
/// Os handlers podem lançá-lo; o middleware de erros transforma em resposta.
class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message);

  const ApiException.badRequest(String message)
    : this(400, 'bad_request', message);

  const ApiException.unauthorized([
    String message = 'Faça login para continuar.',
  ]) : this(401, 'unauthorized', message);

  const ApiException.forbidden(String message)
    : this(403, 'forbidden', message);

  const ApiException.notFound([String message = 'Recurso não encontrado.'])
    : this(404, 'not_found', message);

  const ApiException.conflict(String code, String message)
    : this(409, code, message);

  const ApiException.payloadTooLarge([
    String message = 'O corpo da requisição é grande demais.',
  ]) : this(413, 'payload_too_large', message);

  const ApiException.unsupportedMediaType(String message)
    : this(415, 'unsupported_media_type', message);

  /// Status HTTP.
  final int status;

  /// Código estável, para o cliente tratar sem depender do texto.
  final String code;

  /// Mensagem em português, pronta para exibir.
  final String message;

  Response toResponse() => jsonResponse({
    'error': {'code': code, 'message': message},
  }, status: status);

  @override
  String toString() => 'ApiException($status, $code): $message';
}

class _BodyTooLarge extends ApiException {
  const _BodyTooLarge() : super.payloadTooLarge();
}
