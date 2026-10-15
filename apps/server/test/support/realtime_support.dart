import 'dart:async';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_server/server.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'test_server.dart';

const testDeviceInfo = DeviceInfo(appVersion: '0.5.0', model: 'TV 4K');

/// Cria o administrador e devolve o cabeçalho de sessão.
Future<Map<String, String>> setupAdmin(TestServer server) async {
  final setup = await server.post(
    '/api/v1/setup',
    json: {'username': 'admin', 'password': 'senha-forte-1'},
  );
  return sessionHeader(sessionTokenFrom(setup)!);
}

/// Insere uma TV direto no banco e devolve id e token.
({String id, String token}) insertDevice(
  TestServer server, {
  String name = 'Recepção',
}) {
  final id = generateId();
  final token = generateToken();
  DeviceStore(server.db).create(
    id: id,
    name: name,
    tokenHash: hashToken(token),
    info: testDeviceInfo,
  );
  return (id: id, token: token);
}

Uri wsUri(TestServer server, String path) =>
    server.uri(path).replace(scheme: 'ws');

/// Mensagens recebidas por um WebSocket, lidas uma a uma.
class Inbox {
  Inbox(this.channel) : _iterator = StreamIterator(_decode(channel));

  final WebSocketChannel channel;
  final StreamIterator<Envelope> _iterator;

  static Stream<Envelope> _decode(WebSocketChannel channel) =>
      channel.stream.map((data) => Envelope.decode(data as String));

  /// Próxima mensagem, ou erro se nada chegar em [timeout].
  Future<Envelope> next({Duration timeout = const Duration(seconds: 2)}) async {
    final has = await _iterator.moveNext().timeout(timeout);
    if (!has) throw StateError('conexão fechada');
    return _iterator.current;
  }

  /// Próxima mensagem do tipo [type], ignorando as outras.
  Future<Envelope> nextOfType(String type) async {
    while (true) {
      final envelope = await next();
      if (envelope.type == type) return envelope;
    }
  }

  /// Espera o fechamento e devolve o código.
  Future<int?> closeCode({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    while (await _iterator.moveNext().timeout(timeout)) {}
    return channel.closeCode;
  }
}

/// Conecta uma TV em `/ws/device`.
Future<WebSocketChannel> connectDevice(TestServer server, String? token) async {
  final channel = IOWebSocketChannel.connect(
    wsUri(server, WsPaths.device),
    headers: {if (token != null) 'authorization': 'Bearer $token'},
  );
  await channel.ready;
  addTearDown(() => channel.sink.close());
  return channel;
}

Envelope helloEnvelope({String? currentItem, int v = protocolVersion}) =>
    Envelope(
      v: v,
      type: MessageTypes.hello,
      id: 'h1',
      ts: DateTime.now(),
      payload: HelloPayload(
        deviceInfo: testDeviceInfo,
        currentItem: currentItem,
      ).toJson(),
    );

void sendHello(WebSocketChannel channel, {String? currentItem}) =>
    channel.sink.add(helloEnvelope(currentItem: currentItem).encode());

/// Conecta o dashboard em `/ws/admin` com Origin igual ao servidor.
Future<WebSocketChannel> connectAdmin(
  TestServer server,
  Map<String, String> session, {
  String? origin,
}) async {
  final uri = server.uri('/');
  final channel = IOWebSocketChannel.connect(
    wsUri(server, WsPaths.admin),
    headers: {'origin': origin ?? 'http://${uri.host}:${uri.port}', ...session},
  );
  await channel.ready;
  addTearDown(() => channel.sink.close());
  return channel;
}
