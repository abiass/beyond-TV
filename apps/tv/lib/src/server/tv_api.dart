import 'dart:async';
import 'dart:convert';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:http/http.dart' as http;

import 'server_address.dart';

/// Falha ao falar com o servidor, com mensagem pronta para a tela da TV.
class TvApiException implements Exception {
  const TvApiException(this.message, {this.code});

  final String message;

  /// Código do erro devolvido pelo servidor (ex.: `expired_code`), ou `null`
  /// se o servidor nem respondeu.
  final String? code;

  @override
  String toString() => 'TvApiException($code): $message';
}

/// Cliente HTTP do app da TV.
class TvApi {
  TvApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 8);
  static const unpairTimeout = Duration(seconds: 5);

  /// Confere se [server] é um servidor Beyond TV que está respondendo.
  Future<void> checkServer(ServerAddress server) async {
    final json = await _send(http.Request('GET', server.resolve('/health')));
    if (json['status'] != 'ok') throw _notBeyondServer;
  }

  /// Troca o código de pareamento pelas credenciais da TV.
  ///
  /// Os erros do servidor (código inválido, expirado, muitas tentativas)
  /// chegam como [TvApiException] com a mensagem pronta para a tela.
  Future<PairResponse> pair(ServerAddress server, PairRequest pair) async {
    final request = http.Request('POST', server.resolve('/api/v1/pair'))
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode(pair.toJson());
    final json = await _send(request);
    try {
      return PairResponse.fromJson(json);
    } on ProtocolException {
      throw _notBeyondServer;
    }
  }

  /// Pede ao servidor para aprovar esta TV no painel.
  ///
  /// Um servidor anterior à 1.1 não tem a rota: responde
  /// [TvApiException] com código `not_found`.
  Future<PairRequestTicket> requestApproval(
    ServerAddress server,
    DeviceInfo deviceInfo,
  ) async {
    final request =
        http.Request('POST', server.resolve('/api/v1/pair-requests'))
          ..headers['content-type'] = 'application/json'
          ..body = jsonEncode({'deviceInfo': deviceInfo.toJson()});
    final json = await _send(request);
    try {
      return PairRequestTicket.fromJson(json);
    } on ProtocolException {
      throw _notBeyondServer;
    }
  }

  /// Situação do pedido [ticket]. Pedido esquecido pelo servidor (vencido
  /// há muito, servidor reiniciado) responde código `not_found`.
  Future<PairRequestPoll> pollApproval(
    ServerAddress server,
    PairRequestTicket ticket,
  ) async {
    final request = http.Request('GET', _ticketUri(server, ticket))
      ..headers['Authorization'] = 'Bearer ${ticket.secret}';
    final json = await _send(request);
    try {
      return PairRequestPoll.fromJson(json);
    } on ProtocolException {
      throw _notBeyondServer;
    }
  }

  /// Desiste do pedido [ticket]. Quem chama ignora a falha: o pedido vence
  /// sozinho.
  Future<void> cancelApproval(
    ServerAddress server,
    PairRequestTicket ticket,
  ) async {
    final request = http.Request('DELETE', _ticketUri(server, ticket))
      ..headers['Authorization'] = 'Bearer ${ticket.secret}';
    await _send(request, timeout: unpairTimeout);
  }

  Uri _ticketUri(ServerAddress server, PairRequestTicket ticket) =>
      server.resolve('/api/v1/pair-requests/${Uri.encodeComponent(ticket.id)}');

  /// A TV se remove do servidor (`DELETE /api/v1/device`, com o Bearer da
  /// TV). Quem chama ignora a falha: desparear localmente não depende dele.
  Future<void> unpairSelf(ServerAddress server, String token) async {
    final request = http.Request('DELETE', server.resolve('/api/v1/device'))
      ..headers['Authorization'] = 'Bearer $token';
    await _send(request, timeout: unpairTimeout);
  }

  /// Envia [request] e devolve o corpo JSON.
  ///
  /// Lança [TvApiException] com a mensagem do servidor quando ele responde
  /// com erro, ou com "servidor inacessível" quando não responde.
  Future<Map<String, Object?>> _send(
    http.Request request, {
    Duration timeout = _timeout,
  }) async {
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      ).timeout(timeout);
    } on TimeoutException {
      throw unreachable;
    } on http.ClientException {
      throw unreachable;
    }

    final Object? json;
    try {
      json = response.body.isEmpty
          ? const <String, Object?>{}
          : jsonDecode(response.body);
    } on FormatException {
      throw _notBeyondServer;
    }
    if (json is! Map<String, Object?>) throw _notBeyondServer;

    if (response.statusCode >= 400) {
      throw switch (json['error']) {
        {'code': final String code, 'message': final String message} =>
          TvApiException(message, code: code),
        _ => _notBeyondServer,
      };
    }
    return json;
  }

  static const unreachable = TvApiException(
    'Servidor inacessível. Confira se o servidor está ligado e se a TV está '
    'na mesma rede.',
  );

  static const _notBeyondServer = TvApiException(
    'Esse endereço não é de um servidor Beyond TV.',
  );
}
