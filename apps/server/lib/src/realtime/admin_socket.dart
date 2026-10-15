import 'dart:async';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../auth/sessions.dart';
import '../http/json.dart';
import '../http/middleware.dart';
import 'device_hub.dart';

/// `GET /ws/admin`: eventos ao vivo para o dashboard.
class AdminSocket {
  AdminSocket({required SessionStore sessions, required DeviceHub hub})
    : _sessions = sessions,
      _hub = hub;

  final SessionStore _sessions;
  final DeviceHub _hub;

  FutureOr<Response> handle(Request request) {
    // Ao contrário do REST, aqui a ausência de Origin também é recusada: o
    // canal só serve ao navegador (proteção contra CSWSH).
    final origin = request.headers['origin'];
    if (origin == null || !isSameOrigin(origin, request)) {
      throw const ApiException(
        403,
        'forbidden_origin',
        'Requisição recusada: origem diferente do servidor.',
      );
    }
    final token = SessionStore.tokenOf(request);
    final valid = token != null && _sessions.findAdmin(token) != null;
    return webSocketHandler((WebSocketChannel channel, String? protocol) {
      if (!valid) {
        channel.sink.close(WsCloseCodes.unauthorized, 'unauthorized');
        return;
      }
      final subscription = _hub.events.listen(
        (event) => channel.sink.add(event.encode()),
      );
      // O dashboard não envia nada; só mantém a escuta do `done`.
      channel.stream.listen(
        (_) {},
        onError: (Object _) {},
        onDone: subscription.cancel,
      );
    }, pingInterval: heartbeatInterval)(request);
  }
}
