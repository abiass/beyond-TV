import 'dart:async';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../device/credentials.dart';
import '../device/device_info_source.dart';
import '../remote/app_log.dart';
import '../server/discovery.dart';
import '../server/server_address.dart';
import 'backoff.dart';
import 'socket_connector.dart';

/// Situação da conexão da TV com o servidor.
enum ConnectionStatus {
  connecting,
  online,
  offline,

  /// O servidor recusou o token: a TV foi removida. Não reconecta.
  unauthorized,

  /// Outra conexão da mesma TV tomou o lugar desta. Não reconecta.
  replaced,

  /// Versão de protocolo incompatível. Tenta de novo a cada 5 minutos.
  outdated,
}

/// Mantém a TV conectada ao servidor: conecta, manda `hello` e `heartbeat`,
/// reconecta com backoff e refaz a descoberta se o servidor mudou de IP.
class DeviceConnection extends ChangeNotifier {
  DeviceConnection({
    required Credentials credentials,
    required this.deviceInfo,
    required this.store,
    this.discovery,
    this.connector = ioConnector,
    Backoff? backoff,
    this.heartbeatEvery = heartbeatInterval,
    this.currentItem,
    DateTime Function() now = DateTime.now,
  })  : _credentials = credentials,
        _backoff = backoff ?? Backoff(),
        _now = now;

  final DeviceInfoSource deviceInfo;
  final CredentialStore store;
  final ServerDiscovery? discovery;
  final SocketConnector connector;
  final Duration heartbeatEvery;

  /// O que a TV está exibindo (a URL), enviado no `hello` e no `heartbeat`.
  final String? Function()? currentItem;

  /// Tempo online que faz a próxima queda recomeçar o backoff do zero.
  static const _stableAfter = Duration(seconds: 60);
  static const _outdatedRetry = Duration(minutes: 5);

  final Backoff _backoff;
  final DateTime Function() _now;
  final _messages = StreamController<Envelope>.broadcast();

  Credentials _credentials;
  ConnectionStatus _status = ConnectionStatus.connecting;
  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  Timer? _heartbeat;
  Timer? _retryTimer;
  DateTime? _retryAt;
  DateTime? _onlineSince;
  late final DateTime _startedAt = _now();
  bool _started = false;
  bool _disposed = false;

  ConnectionStatus get status => _status;

  /// Credenciais em uso; mudam se o servidor trocou de IP.
  Credentials get credentials => _credentials;

  /// Quanto falta para a próxima tentativa, quando está `offline`.
  Duration? get nextRetryIn {
    final at = _retryAt;
    if (at == null) return null;
    final left = at.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  /// Mensagens do servidor já decodificadas (a fase 6 trata os comandos
  /// aqui). Tipos desconhecidos também chegam; quem ouve decide ignorar.
  Stream<Envelope> get messages => _messages.stream;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    unawaited(_connect());
  }

  Uri get _uri {
    final server = _credentials.server;
    return Uri(
      scheme: 'ws',
      host: server.host,
      port: server.port,
      path: WsPaths.device,
    );
  }

  Future<void> _connect() async {
    if (_disposed) return;
    _retryTimer?.cancel();
    _retryAt = null;
    _setStatus(ConnectionStatus.connecting);

    final WebSocketChannel channel;
    try {
      channel = await connector(_uri, {
        'authorization': 'Bearer ${_credentials.deviceToken}',
      });
    } on Object {
      await _scheduleRetry();
      return;
    }
    if (_disposed) {
      unawaited(_closeQuietly(channel));
      return;
    }
    _channel = channel;
    _subscription = channel.stream.listen(
      _onData,
      onError: (Object _) => _onClosed(channel),
      onDone: () => _onClosed(channel),
      cancelOnError: true,
    );

    try {
      await _sendHello(channel);
    } on Object {
      // O canal caiu antes do hello; o `onDone` cuida da reconexão.
      return;
    }
    if (_disposed || _channel != channel) return;
    _onlineSince = _now();
    _heartbeat = Timer.periodic(heartbeatEvery, (_) => _sendHeartbeat(channel));
    _setStatus(ConnectionStatus.online);
  }

  Future<void> _sendHello(WebSocketChannel channel) async {
    final info = await deviceInfo.read();
    _send(
      channel,
      MessageTypes.hello,
      HelloPayload(deviceInfo: info, currentItem: currentItem?.call()).toJson(),
    );
  }

  void _sendHeartbeat(WebSocketChannel channel) {
    try {
      _send(
        channel,
        MessageTypes.heartbeat,
        HeartbeatPayload(
          uptimeSeconds: _now().difference(_startedAt).inSeconds,
          currentItem: currentItem?.call(),
        ).toJson(),
      );
    } on Object {
      // Se o canal caiu, o `onDone` já está a caminho.
    }
  }

  void _send(
    WebSocketChannel channel,
    String type,
    Map<String, Object?> payload,
  ) {
    channel.sink.add(Envelope.create(type, payload: payload).encode());
  }

  /// Envia [envelope] ao servidor, só se a TV está `online`.
  void send(Envelope envelope) {
    final channel = _channel;
    if (_status != ConnectionStatus.online || channel == null) return;
    try {
      channel.sink.add(envelope.encode());
    } on Object {
      // Se o canal caiu, o `onDone` já está a caminho.
    }
  }

  /// A TV foi removida pelo painel (`cmd.unpair`): para de reconectar e
  /// vira `unauthorized`, sem esperar o `4401` do servidor.
  void markUnauthorized() {
    if (_disposed || _status == ConnectionStatus.unauthorized) return;
    _retryTimer?.cancel();
    _heartbeat?.cancel();
    final channel = _channel;
    _channel = null;
    _onlineSince = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    if (channel != null) unawaited(_closeQuietly(channel));
    _setStatus(ConnectionStatus.unauthorized);
  }

  void _onData(Object? data) {
    if (data is! String) return;
    try {
      _messages.add(Envelope.decode(data));
    } on ProtocolException {
      // Mensagem fora do protocolo: ignora.
    }
  }

  Future<void> _onClosed(WebSocketChannel channel) async {
    if (_disposed || _channel != channel) return;
    _channel = null;
    _heartbeat?.cancel();
    final onlineSince = _onlineSince;
    _onlineSince = null;
    unawaited(_subscription?.cancel());
    _subscription = null;

    if (onlineSince != null && _now().difference(onlineSince) > _stableAfter) {
      _backoff.reset();
    }

    switch (channel.closeCode) {
      case WsCloseCodes.unauthorized:
        try {
          await store.clear();
        } on Object {
          // Sem como apagar agora; a TV ainda sai do fluxo.
        }
        _setStatus(ConnectionStatus.unauthorized);
      case WsCloseCodes.replaced:
        _setStatus(ConnectionStatus.replaced);
      case WsCloseCodes.incompatibleVersion:
        _retryAt = _now().add(_outdatedRetry);
        _retryTimer = Timer(_outdatedRetry, _connect);
        _setStatus(ConnectionStatus.outdated);
      default:
        await _scheduleRetry();
    }
  }

  Future<void> _scheduleRetry() async {
    if (_disposed) return;
    final delay = _backoff.next();
    _retryAt = _now().add(delay);
    _setStatus(ConnectionStatus.offline);
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, _connect);

    if (discovery != null && _backoff.failures % 3 == 0) {
      if (await _rediscover()) {
        _retryTimer?.cancel();
        unawaited(_connect());
      }
    }
  }

  /// Procura o mesmo servidor (`serverId`) em outro endereço. Devolve `true`
  /// se o endereço salvo mudou.
  Future<bool> _rediscover() async {
    try {
      final found = await discovery!.discover();
      if (_disposed) return false;
      final current = _credentials.server;
      for (final server in found) {
        if (server.serverId == null || server.serverId != current.serverId) {
          continue;
        }
        if (server.host == current.host && server.port == current.port) {
          return false;
        }
        final updated = Credentials(
          deviceId: _credentials.deviceId,
          deviceToken: _credentials.deviceToken,
          server: ServerAddress(
            host: server.host,
            port: server.port,
            name: server.name ?? current.name,
            serverId: current.serverId,
          ),
        );
        await store.save(updated);
        _credentials = updated;
        return true;
      }
    } on Object {
      // Descoberta falhou: segue com o backoff.
    }
    return false;
  }

  void _setStatus(ConnectionStatus status) {
    if (_disposed) return;
    if (status != _status) appLog('Conexão: ${status.name}');
    _status = status;
    notifyListeners();
  }

  static Future<void> _closeQuietly(WebSocketChannel channel) async {
    try {
      await channel.sink.close(1000);
    } on Object {
      // Já estava fechado.
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _retryTimer?.cancel();
    _heartbeat?.cancel();
    final channel = _channel;
    _channel = null;
    await _subscription?.cancel();
    await _messages.close();
    if (channel != null) await _closeQuietly(channel);
    super.dispose();
  }
}
