import 'dart:async';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Canal WebSocket em memória: grava o que a TV envia e deixa o teste
/// fechar com um código.
class FakeWebSocketChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  FakeWebSocketChannel() {
    sink = _FakeSink(this);
  }

  final _incoming = StreamController<dynamic>();
  final List<String> sent = [];

  @override
  int? closeCode;

  @override
  String? closeReason;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future.value();

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  late final WebSocketSink sink;

  /// Mensagens enviadas, decodificadas.
  List<Envelope> get envelopes => [for (final s in sent) Envelope.decode(s)];

  /// O servidor fecha a conexão.
  void serverClose(int code) {
    closeCode = code;
    _incoming.close();
  }

  void serverSend(Envelope envelope) => _incoming.add(envelope.encode());

  void serverSendRaw(String text) => _incoming.add(text);
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._channel);

  final FakeWebSocketChannel _channel;
  final _done = Completer<void>();

  @override
  void add(dynamic data) => _channel.sent.add(data as String);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) => stream.forEach(add);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _channel.closeCode ??= closeCode;
    if (!_channel._incoming.isClosed) await _channel._incoming.close();
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}

/// Conector falso: cada chamada registra a URI e os headers e devolve o
/// próximo canal da fila, ou lança se a fila acabou ou [failures] > 0.
class FakeConnector {
  final List<FakeWebSocketChannel> channels = [];
  final List<Uri> uris = [];
  final List<Map<String, String>> headers = [];

  /// Quantas tentativas ainda falham antes de aceitar.
  int failures = 0;

  Future<WebSocketChannel> call(Uri uri, Map<String, String> h) async {
    uris.add(uri);
    headers.add(h);
    if (failures > 0) {
      failures--;
      throw const _Refused();
    }
    final channel = FakeWebSocketChannel();
    channels.add(channel);
    return channel;
  }

  FakeWebSocketChannel get last => channels.last;
}

class _Refused implements Exception {
  const _Refused();
}
