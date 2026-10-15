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
import 'screenshots.dart';

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

/// Tamanho máximo de uma mensagem da TV (texto): base64 de uma captura de
/// [maxScreenshotBytes] (cerca de 2,7 MiB) mais o envelope. Passou disso, a
/// conexão é fechada com [WsCloseCodes.protocolError] (o `dart:io` não deixa
/// usar o 1009); a TV reconecta sozinha.
const maxDeviceMessageChars = 3 * 1024 * 1024;

/// `GET /ws/device`: conexão em tempo real de cada TV.
class DeviceSocket {
  DeviceSocket({
    required DeviceStore devices,
    required DeviceHub hub,
    required ContentSync sync,
    required ScreenshotStore screenshots,
    RealtimeTimeouts timeouts = const RealtimeTimeouts(),
  }) : _devices = devices,
       _hub = hub,
       _sync = sync,
       _screenshots = screenshots,
       _timeouts = timeouts;

  final DeviceStore _devices;
  final DeviceHub _hub;
  final ContentSync _sync;
  final ScreenshotStore _screenshots;
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
      if (data.length > maxDeviceMessageChars) {
        return fail(WsCloseCodes.protocolError, 'message too big');
      }
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
        } else if (envelope.type == MessageTypes.screenshotResult) {
          _onScreenshotResult(device.id, envelope);
        } else if (envelope.type == MessageTypes.error) {
          _onDeviceError(device.id, envelope);
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

  void _onScreenshotResult(String deviceId, Envelope envelope) {
    final String? reason;
    DateTime? capturedAt;
    try {
      final result = ScreenshotResult.fromJson(envelope.payload);
      reason = _screenshots.accept(deviceId, result);
      capturedAt = _screenshots.latest(deviceId)?.capturedAt;
    } on ProtocolException {
      _log.warning(
        LogEvent('captura descartada', {
          'deviceId': deviceId,
          'reason': 'invalid_payload',
        }),
      );
      return;
    }
    if (reason != null || capturedAt == null) {
      _log.warning(
        LogEvent('captura descartada', {
          'deviceId': deviceId,
          'reason': reason ?? 'unknown',
        }),
      );
      return;
    }
    _hub.publish(
      MessageTypes.deviceScreenshot,
      DeviceScreenshotEvent(
        deviceId: deviceId,
        capturedAt: capturedAt,
      ).toJson(),
    );
    _log.info(LogEvent('captura recebida', {'deviceId': deviceId}));
  }

  void _onDeviceError(String deviceId, Envelope envelope) {
    try {
      final error = ErrorPayload.fromJson(envelope.payload);
      _screenshots.dropByRef(deviceId, error.ref);
      _log.info(
        LogEvent('erro informado pela TV', {
          'deviceId': deviceId,
          'code': error.code,
        }),
      );
    } on ProtocolException {
      _log.fine(LogEvent('erro inválido ignorado', {'deviceId': deviceId}));
    }
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
