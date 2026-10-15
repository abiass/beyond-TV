import 'dart:convert';

import 'envelope.dart';
import 'json_fields.dart';
import 'protocol_exception.dart';

/// Porta UDP em que o servidor escuta a descoberta.
const discoveryPort = 8788;

/// Mensagem que a TV envia em broadcast para achar servidores.
const discoveryRequest = 'BEYONDTV_DISCOVER v$protocolVersion';

/// Resposta do servidor à descoberta, enviada em unicast para a TV.
///
/// Não traz o IP do servidor: a TV usa o endereço de origem do pacote, que é
/// sempre o IP do servidor na rede em que a TV está.
final class DiscoveryResponse {
  const DiscoveryResponse({
    required this.name,
    required this.port,
    required this.serverId,
    this.v = protocolVersion,
  });

  /// Lê a resposta de um datagrama UDP.
  factory DiscoveryResponse.decode(List<int> bytes) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (e) {
      throw ProtocolException('resposta de descoberta inválida: ${e.message}');
    }
    if (json is! Map<String, Object?>) {
      throw const ProtocolException('a resposta deve ser um objeto JSON');
    }
    final port = json.field<int>('port');
    if (port < 1 || port > 65535) {
      throw const ProtocolException('campo "port" fora do intervalo');
    }
    return DiscoveryResponse(
      name: json.field<String>('name'),
      port: port,
      serverId: json.field<String>('serverId'),
      v: json.field<int>('v'),
    );
  }

  /// Nome do servidor exibido na TV (o nome do PC).
  final String name;

  /// Porta HTTP do servidor.
  final int port;
  final String serverId;

  /// Versão do protocolo do servidor.
  final int v;

  List<int> encode() => utf8.encode(
        jsonEncode({'v': v, 'name': name, 'port': port, 'serverId': serverId}),
      );

  @override
  String toString() => 'DiscoveryResponse($name:$port, server: $serverId)';
}
