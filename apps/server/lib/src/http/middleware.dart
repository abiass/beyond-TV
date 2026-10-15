import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';

import '../logging.dart';
import 'json.dart';

final _log = Logger('http');

/// Registra cada requisição com método, caminho, status e duração.
///
/// Sucesso sai em `debug`, erro do cliente (4xx) em `info` e erro do servidor
/// (5xx) em `warning`.
///
/// A *query string* fica de fora porque pode carregar tokens.
Middleware requestLogger() =>
    (inner) => (request) async {
      final watch = Stopwatch()..start();
      final response = await inner(request);
      final status = response.statusCode;
      _log.log(
        switch (status) {
          >= 500 => Level.WARNING,
          >= 400 => Level.INFO,
          _ => Level.FINE,
        },
        LogEvent('requisição', {
          'method': request.method,
          'path': request.requestedUri.path,
          'status': status,
          'ms': watch.elapsedMilliseconds,
        }),
      );
      return response;
    };

/// Recusa com `403` requisições que alteram dados (`POST`, `PUT`, `PATCH`,
/// `DELETE`...) vindas de outra origem.
///
/// É a defesa contra CSRF junto com o cookie `SameSite=Strict`: o navegador
/// sempre manda o `Origin` nesses métodos, e ele tem que bater com o `Host`.
/// Clientes que não são navegador (como o app da TV) não mandam `Origin` e
/// passam direto; eles se autenticam por token, não por cookie.
Middleware originCheck() =>
    (inner) => (request) {
      final origin = request.headers['origin'];
      if (origin != null &&
          !_safeMethods.contains(request.method) &&
          !isSameOrigin(origin, request)) {
        throw const ApiException(
          403,
          'forbidden_origin',
          'Requisição recusada: origem diferente do servidor.',
        );
      }
      return inner(request);
    };

const _safeMethods = {'GET', 'HEAD', 'OPTIONS'};

/// Indica se o cabeçalho `Origin` [origin] aponta para o próprio servidor.
bool isSameOrigin(String origin, Request request) {
  final host = request.headers['host'];
  final scheme = request.requestedUri.scheme;
  final originUri = Uri.tryParse(origin);
  if (host == null ||
      originUri == null ||
      !originUri.hasAuthority ||
      originUri.scheme != scheme) {
    return false;
  }
  // Interpreta o Host com o esquema do servidor para normalizar a porta padrão.
  final hostUri = Uri.tryParse('$scheme://$host');
  return hostUri != null &&
      hostUri.host == originUri.host &&
      hostUri.port == originUri.port;
}

/// Transforma exceções em respostas JSON.
///
/// [ApiException] vira a resposta que ela descreve. Qualquer outro erro é
/// registrado com o stack trace e vira um `500` genérico, sem vazar detalhes
/// internos para o cliente.
Middleware errorHandler() =>
    (inner) => (request) async {
      try {
        return await inner(request);
      } on HijackException {
        // Usada pelo shelf para entregar o socket ao WebSocket.
        rethrow;
      } on ApiException catch (e) {
        return e.toResponse();
      } on Object catch (e, stackTrace) {
        _log.severe(
          LogEvent('erro não tratado', {
            'method': request.method,
            'path': request.requestedUri.path,
          }),
          e,
          stackTrace,
        );
        return const ApiException(
          500,
          'internal_error',
          'Erro interno do servidor.',
        ).toResponse();
      }
    };
