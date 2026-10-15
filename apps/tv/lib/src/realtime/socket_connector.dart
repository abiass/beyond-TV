import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Abre um WebSocket. Os testes trocam por um falso para não usar a rede.
typedef SocketConnector = Future<WebSocketChannel> Function(
  Uri uri,
  Map<String, String> headers,
);

/// Conector real: espera o upgrade terminar antes de devolver o canal.
Future<WebSocketChannel> ioConnector(
  Uri uri,
  Map<String, String> headers,
) async {
  final channel = IOWebSocketChannel.connect(
    uri,
    headers: headers,
    pingInterval: heartbeatInterval,
  );
  await channel.ready;
  return channel;
}
