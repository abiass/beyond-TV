import 'dart:async';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../auth/tokens.dart';
import '../devices/devices.dart';
import '../logging.dart';
import 'content_sync.dart';
import 'device_hub.dart';

final _log = Logger('realtime.device');

/// Prazos do `/ws/device`. Os testes usam valores curtos.
class RealtimeTimeouts {
  const RealtimeTimeouts({
    this.hello = helloTimeout,
    this.silence = deviceSilenceTimeout,
  });

  /// Prazo para o `hello` depois do upgrade.
  final Duration hello;

  /// Silêncio máximo da TV depois do `hello`.
  final Duration silence;
}

/// `GET /ws/device`: conexão em tempo real de cada TV.
class DeviceSocket {
  DeviceSocket({
    required DeviceStore devices,
    required DeviceHub hub,
    required ContentSync sync,
    RealtimeTimeouts timeouts = const RealtimeTimeouts(),
  }) : _devices = devices,
       _hub = hub,
       _sync = sync,
       _timeouts = timeouts;

  final DeviceStore _devices;
  final DeviceHub _hub;
  final ContentSync _sync;
  final RealtimeTimeouts _timeouts;

  /// Handler da rota; autentica pelo cabeçalho antes do upgrade.
  FutureOr<Response> handle(Request request) {
    final token = bearerTokenOf(request);
    final device = token == null
        ? null
        : _devices.findByTokenHash(hashToken(token));
    return webSocketHandler(
      (WebSocketChannel channel, String? protocol) =>
          _onConnection(channel, device),
      pingInterval: heartbeatInterval,
    )(request);
  }

  void _onConnection(
    WebSocketChannel channel,
    ({String id, String name})? device,
  ) {
    if (device == null) {
      _log.info(const LogEvent('conexão de TV recusada'));
      channel.sink.close(WsCloseCodes.unauthorized, 'unauthorized');
      return;
    }

    final conn = _ChannelConnection(channel);
    var closed = false;
    var greeted = false;
    Timer? helloTimer;
    Timer? silenceTimer;

    void fail(int code, String reason) {
      if (closed) return;
      closed = true;
      _log.info(
        LogEvent('conexão de TV encerrada', {
          'deviceId': device.id,
          'code': code,
          'reason': reason,
        }),
      );
      channel.sink.close(code, reason);
    }

    void resetSilence() {
      silenceTimer?.cancel();
      silenceTimer = Timer(
        _timeouts.silence,
        () => fail(WsCloseCodes.protocolError, 'silence'),
      );
    }

    helloTimer = Timer(
      _timeouts.hello,
      () => fail(WsCloseCodes.protocolError, 'hello timeout'),
    );

    void onData(Object? data) {
      if (closed) return;
      if (data is! String) return fail(WsCloseCodes.protocolError, 'text only');
      final Envelope envelope;
      try {
        envelope = Envelope.decode(data);
      } on ProtocolException {
        return fail(WsCloseCodes.protocolError, 'invalid envelope');
      }
      if (!envelope.isCompatible) {
        conn.send(
          Envelope.create(
            MessageTypes.error,
            payload: {
              'code': 'incompatible_version',
              'message': 'Atualize o app da TV.',
            },
          ),
        );
        return fail(WsCloseCodes.incompatibleVersion, 'incompatible version');
      }

      try {
        if (!greeted) {
          if (envelope.type != MessageTypes.hello) {
            return fail(WsCloseCodes.protocolError, 'hello expected');
          }
          final hello = HelloPayload.fromJson(envelope.payload);
          greeted = true;
          helloTimer?.cancel();
          _devices.updateInfo(device.id, hello.deviceInfo);
          _hub.attach(device.id, conn);
          _hub.markSeen(
            device.id,
            currentItem: hello.currentItem,
            announce: false,
          );
          _hub.publish(MessageTypes.deviceOnline, {'deviceId': device.id});
          final row = _devices.find(device.id);
          if (row != null) {
            _hub.publish(
              MessageTypes.deviceState,
              _hub.summaryOf(row).toJson(),
            );
          }
          _sync.syncDevice(device.id);
          _log.info(LogEvent('TV online', {'deviceId': device.id}));
        } else if (envelope.type == MessageTypes.heartbeat) {
          final beat = HeartbeatPayload.fromJson(envelope.payload);
          _hub.markSeen(device.id, currentItem: beat.currentItem);
        } else if (envelope.type == MessageTypes.ack) {
          try {
            final ack = AckPayload.fromJson(envelope.payload);
            _log.fine(LogEvent('ack', {'deviceId': device.id, 'ref': ack.ref}));
          } on ProtocolException {
            _log.fine(
              LogEvent('ack inválido ignorado', {'deviceId': device.id}),
            );
          }
        } else {
          _log.fine(
            LogEvent('mensagem ignorada', {
              'deviceId': device.id,
              'type': envelope.type,
            }),
          );
        }
      } on ProtocolException {
        return fail(WsCloseCodes.protocolError, 'invalid payload');
      }
      if (greeted) resetSilence();
    }

    channel.stream.listen(
      onData,
      onError: (Object _) {},
      onDone: () {
        closed = true;
        helloTimer?.cancel();
        silenceTimer?.cancel();
        _hub.detach(device.id, conn);
      },
      cancelOnError: false,
    );
  }
}

class _ChannelConnection implements DeviceConnection {
  _ChannelConnection(this._channel);

  final WebSocketChannel _channel;

  @override
  void send(Envelope envelope) => _channel.sink.add(envelope.encode());

  @override
  Future<void> close(int code, String reason) =>
      _channel.sink.close(code, reason);
}
