import 'dart:async';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../auth/auth_controller.dart';

/// Abre o WebSocket em [uri]. Os testes trocam por um falso.
typedef AdminSocketConnector = WebSocketChannel Function(Uri uri);

/// No navegador o cookie de sessão vai sozinho, na mesma origem.
final adminSocketConnectorProvider = Provider<AdminSocketConnector>(
  (ref) => WebSocketChannel.connect,
);

/// Endereço do `WS /ws/admin` a partir da origem HTTP do servidor.
Uri adminSocketUri(Uri base) => Uri(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: WsPaths.admin,
    );

/// Canal de eventos ao vivo do servidor, com reconexão automática.
class AdminEvents {
  AdminEvents({
    required Uri uri,
    required AdminSocketConnector connector,
    required void Function() onUnauthorized,
  })  : _uri = uri,
        _connector = connector,
        _onUnauthorized = onUnauthorized;

  final Uri _uri;
  final AdminSocketConnector _connector;
  final void Function() _onUnauthorized;

  final _events = StreamController<Envelope>.broadcast();
  final _connectionChanges = StreamController<bool>.broadcast();

  bool _connected = false;
  bool _stopped = false;
  bool _connecting = false;
  int _attempt = 0;
  Timer? _retryTimer;
  StreamSubscription<Object?>? _subscription;

  /// Mensagens recebidas do servidor.
  Stream<Envelope> get events => _events.stream;

  /// Estado da conexão: emite o valor atual ao assinar e depois as mudanças.
  Stream<bool> get connected =>
      Stream.multi(_listenConnected, isBroadcast: true);

  void _listenConnected(MultiStreamController<bool> controller) {
    controller.add(_connected);
    final sub = _connectionChanges.stream.listen(controller.add);
    controller.onCancel = sub.cancel;
  }

  /// Tempo de espera antes da tentativa número [attempt] (0, 1, 2…).
  static Duration backoff(int attempt) =>
      Duration(seconds: attempt >= 5 ? 30 : 1 << attempt);

  void start() {
    if (_stopped ||
        _connecting ||
        _subscription != null ||
        _retryTimer != null) {
      return;
    }
    unawaited(_connect());
  }

  Future<void> _connect() async {
    final WebSocketChannel channel;
    _connecting = true;
    try {
      channel = _connector(_uri);
      await channel.ready;
    } on Object {
      _scheduleRetry();
      return;
    } finally {
      _connecting = false;
    }
    if (_stopped) {
      unawaited(channel.sink.close());
      return;
    }
    _attempt = 0;
    _setConnected(true);
    _subscription = channel.stream.listen(
      (data) {
        if (data is! String) return;
        try {
          _events.add(Envelope.decode(data));
        } on ProtocolException {
          // Mensagem inválida: ignora.
        }
      },
      onError: (Object _) {},
      onDone: () => _closed(channel.closeCode),
    );
  }

  void _closed(int? code) {
    _subscription = null;
    _setConnected(false);
    if (_stopped) return;
    if (code == WsCloseCodes.unauthorized) {
      _stopped = true;
      _onUnauthorized();
      return;
    }
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_stopped) return;
    final delay = backoff(_attempt++);
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_connect());
    });
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    if (!_connectionChanges.isClosed) _connectionChanges.add(value);
  }

  void dispose() {
    _stopped = true;
    _retryTimer?.cancel();
    _subscription?.cancel();
    _events.close();
    _connectionChanges.close();
  }
}

/// Canal ao vivo do painel; abre ao ser lido e fecha quando ninguém usa.
final adminEventsProvider = Provider.autoDispose<AdminEvents>((ref) {
  final events = AdminEvents(
    uri: adminSocketUri(ref.read(apiClientProvider).baseUri),
    connector: ref.read(adminSocketConnectorProvider),
    onUnauthorized: () => ref.read(authProvider.notifier).sessionExpired(),
  )..start();
  ref.onDispose(events.dispose);
  return events;
});

/// Se o canal ao vivo está conectado agora.
final adminConnectedProvider = StreamProvider.autoDispose<bool>(
  (ref) => ref.watch(adminEventsProvider).connected,
);
