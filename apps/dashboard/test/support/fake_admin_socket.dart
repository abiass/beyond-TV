import 'dart:async';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// `WS /ws/admin` falso: os testes empurram eventos e fecham com um código.
class FakeAdminSocket
    with StreamChannelMixin<Object?>
    implements WebSocketChannel {
  final _controller = StreamChannelController<Object?>(sync: true);
  int? _closeCode;

  /// Entrega [event] ao dashboard, como se viesse do servidor.
  void emit(Envelope event) => _controller.foreign.sink.add(event.encode());

  /// Entrega [data] crua, sem passar por [Envelope], para testar lixo.
  void emitRaw(Object? data) => _controller.foreign.sink.add(data);

  /// Fecha a conexão como o servidor, com [code].
  void closeWith(int code) {
    _closeCode = code;
    _controller.foreign.sink.close();
  }

  @override
  Stream<Object?> get stream => _controller.local.stream;

  @override
  WebSocketSink get sink => _FakeSink(_controller.local.sink);

  @override
  Future<void> get ready => Future.value();

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._inner);

  final StreamSink<Object?> _inner;

  @override
  void add(Object? data) => _inner.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<Object?> stream) => _inner.addStream(stream);

  @override
  Future<void> close([int? closeCode, String? closeReason]) => _inner.close();

  @override
  Future<void> get done => _inner.done;
}
