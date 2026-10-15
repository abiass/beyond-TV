import 'dart:async';
import 'dart:io';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/foundation.dart';

import '../device/credentials.dart';
import '../media/media_cache.dart';
import '../player/web_player.dart';
import '../server/tv_api.dart';
import '../realtime/backoff.dart';
import '../realtime/device_connection.dart';
import 'active_content.dart';
import 'manifest_store.dart';
import '../remote/app_log.dart';
import '../remote/screen_capturer.dart';

/// Guarda o que a TV exibe e executa as mensagens do servidor:
/// `content.sync`, `cmd.reload`, `cmd.identify` e `cmd.unpair`.
/// Toda mensagem tratada recebe `ack`.
class ContentController extends ChangeNotifier {
  ContentController({
    required this.store,
    required this.connection,
    this.credentials,
    this.cache,
    this.api,
    this.screenCapturer,
    this.backoffFactory = Backoff.new,
    this.wait = Future.delayed,
    DateTime Function()? now,
  }) : _active = ActiveContent(now: now) {
    _active.addListener(_onActiveChanged);
  }

  final ManifestStore store;
  final DeviceConnection connection;

  /// Apagadas no `cmd.unpair`.
  final CredentialStore? credentials;

  /// Cache dos arquivos de imagem e vídeo; sem ele só sites são exibidos.
  final MediaCache? cache;

  /// Usada em [unpairSelf] para avisar o servidor.
  final TvApi? api;

  /// Captura de tela do `cmd.screenshot`; sem ele a TV responde com erro.
  final ScreenCapturer? screenCapturer;

  /// Espera entre tentativas de download; os testes usam esperas curtas.
  final Backoff Function() backoffFactory;
  final Future<void> Function(Duration) wait;

  final ActiveContent _active;
  ContentManifest _manifest = ContentManifest.empty;
  StreamSubscription<Envelope>? _subscription;
  WebPlayerController? _player;
  Timer? _identifyTimer;
  String? _identifyName;
  bool _synced = false;
  bool _wasUnauthorized = false;
  bool _disposed = false;
  final Set<String> _ready = {};
  int _mediaRun = 0;
  bool _shownReported = false;
  ContentItem? _shown;

  ContentManifest get manifest => _manifest;

  /// Itens da agenda em vigor agora (padrão ou regra ativa).
  List<ContentItem> get activeItems => _active.items;

  /// Muda quando a rotação precisa recomeçar (manifesto ou faixa nova).
  int get activeVersion => _active.version;

  void _onActiveChanged() {
    if (!_disposed) notifyListeners();
  }

  void _setManifest(ContentManifest manifest) {
    _manifest = manifest;
    _active.setManifest(manifest);
  }

  /// Nome do overlay de identificação, enquanto estiver visível.
  String? get identifyName => _identifyName;

  /// URL do primeiro item `url`, ou `null` sem conteúdo.
  String? get currentUrl {
    for (final item in _active.items) {
      if (item.kind == MediaKinds.url && item.url != null) return item.url;
    }
    return null;
  }

  /// A página informa o item que está na tela (`null`: nenhum).
  void reportShown(ContentItem? item) {
    _shownReported = true;
    _shown = item;
  }

  /// Nome do item exibido (a URL, para sites), para o `currentItem` do
  /// servidor. Antes de a página informar, vale a URL do primeiro site.
  String? get currentItem {
    if (!_shownReported) return currentUrl;
    final item = _shown;
    if (item == null) return null;
    return item.kind == MediaKinds.url ? item.url : item.name;
  }

  /// O item já pode ser exibido: site, ou arquivo já em cache.
  bool isReady(ContentItem item) =>
      item.kind == MediaKinds.url ||
      (item.sha256 != null && _ready.contains(item.sha256));

  /// Arquivo em cache do item de imagem ou vídeo, se já foi baixado.
  File? fileFor(ContentItem item) =>
      item.sha256 == null ? null : cache?.cached(item.sha256!);

  /// Recarrega o item em exibição (o mesmo que o `cmd.reload`).
  Future<void> reload() async => _player?.reload();

  /// Tamanho do cache de mídia, ou `null` sem cache.
  Future<CacheStats?> cacheStats() async => cache?.stats();

  /// Controle do player aberto; `null` no estado vazio.
  set player(WebPlayerController? value) => _player = value;

  /// Carrega o manifesto salvo e passa a ouvir o servidor.
  Future<void> start() async {
    _subscription ??= connection.messages.listen(_onMessage);
    connection.addListener(_onConnectionChanged);
    final saved = await store.load();
    // Um sync que chegou durante a leitura é mais novo que o disco.
    if (saved != null && !_synced && !_disposed) {
      _setManifest(saved);
      _startMediaSync(saved);
      notifyListeners();
    }
  }

  void _onConnectionChanged() {
    final unauthorized = connection.status == ConnectionStatus.unauthorized;
    if (unauthorized && !_wasUnauthorized) {
      // 4401: a TV não pertence mais ao servidor.
      unawaited(_clearManifest());
    }
    _wasUnauthorized = unauthorized;
  }

  Future<void> _clearManifest() async {
    try {
      await store.clear();
    } on Object catch (e) {
      appLog('Falha ao apagar o manifesto: $e');
    }
  }

  void _onMessage(Envelope envelope) {
    switch (envelope.type) {
      case MessageTypes.contentSync:
        _onSync(envelope);
      case MessageTypes.cmdReload:
        _ack(envelope);
        unawaited(_player?.reload());
      case MessageTypes.cmdIdentify:
        _onIdentify(envelope);
      case MessageTypes.cmdUnpair:
        unawaited(_onUnpair(envelope));
      case MessageTypes.cmdScreenshot:
        unawaited(_onScreenshot(envelope));
    }
  }

  void _onSync(Envelope envelope) {
    final ContentManifest incoming;
    try {
      incoming = ContentManifest.fromJson(envelope.payload);
    } on ProtocolException catch (e) {
      appLog('content.sync inválido: $e');
      return;
    }
    _synced = true;
    if (incoming.revision != _manifest.revision) {
      // Defesa extra: o servidor já valida, mas a TV não confia.
      List<ContentItem> keepSafe(List<ContentItem> items) => [
            for (final item in items)
              if (_isSafe(item)) item,
          ];
      final safe = ContentManifest(
        items: keepSafe(incoming.items),
        schedules: [
          for (final rule in incoming.schedules)
            ScheduleRule(
              id: rule.id,
              days: rule.days,
              startMinute: rule.startMinute,
              endMinute: rule.endMinute,
              priority: rule.priority,
              target: rule.target,
              items: keepSafe(rule.items),
            ),
        ],
      );
      appLog('Conteúdo sincronizado: revisão ${safe.revision}.');
      _setManifest(safe);
      _startMediaSync(safe);
      notifyListeners();
      unawaited(_save(safe));
    }
    _ack(envelope);
  }

  bool _isSafe(ContentItem item) => switch (item.kind) {
        MediaKinds.url => item.url != null && isSafeContentUrl(item.url!),
        MediaKinds.image ||
        MediaKinds.video =>
          item.sha256 != null && isSha256Hex(item.sha256!),
        _ => true,
      };

  /// Baixa os arquivos do [manifest] e, depois da primeira rodada, apaga os
  /// que ele não usa. Falhas são repetidas com backoff enquanto o manifesto
  /// for o mesmo.
  void _startMediaSync(ContentManifest manifest) {
    final cache = this.cache;
    final run = ++_mediaRun;
    if (cache == null) return;
    final shas = {
      for (final item in manifest.allItems)
        if (item.sha256 != null) item.sha256!,
    };
    _ready.removeWhere((sha) => !shas.contains(sha));
    unawaited(_syncMedia(cache, manifest, shas, run));
  }

  Future<void> _syncMedia(
    MediaCache cache,
    ContentManifest manifest,
    Set<String> shas,
    int run,
  ) async {
    bool stale() => _disposed || run != _mediaRun;
    final credentials = connection.credentials;
    final base = credentials.server.resolve('/');
    final backoff = backoffFactory();
    final pending = <String, ContentItem>{
      for (final item in manifest.allItems)
        if (item.sha256 != null) item.sha256!: item,
    };
    var first = true;
    while (pending.isNotEmpty) {
      for (final sha in pending.keys.toList()) {
        if (stale()) return;
        try {
          await cache.ensure(
            pending[sha]!,
            base: base,
            token: credentials.deviceToken,
          );
        } on Object catch (e) {
          // Nunca inclui o token na mensagem.
          appLog('Falha ao baixar a mídia ${pending[sha]!.mediaId}: $e');
          continue;
        }
        if (stale()) return;
        pending.remove(sha);
        _ready.add(sha);
        appLog('Mídia baixada: ${pending.length} pendente(s).');
        notifyListeners();
      }
      if (first) {
        first = false;
        try {
          await cache.prune(shas);
        } on Object catch (e) {
          appLog('Falha ao limpar o cache de mídia: $e');
        }
      }
      if (pending.isEmpty || stale()) return;
      await wait(backoff.next());
      if (stale()) return;
    }
  }

  Future<void> _save(ContentManifest manifest) async {
    try {
      await store.save(manifest);
    } on Object catch (e) {
      appLog('Falha ao salvar o manifesto: $e');
    }
  }

  void _onIdentify(Envelope envelope) {
    _ack(envelope);
    final IdentifyPayload payload;
    try {
      payload = IdentifyPayload.fromJson(envelope.payload);
    } on ProtocolException catch (e) {
      appLog('cmd.identify inválido: $e');
      return;
    }
    _identifyTimer?.cancel();
    _identifyName = payload.name;
    notifyListeners();
    _identifyTimer = Timer(Duration(seconds: payload.durationSeconds), () {
      _identifyName = null;
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> _onScreenshot(Envelope envelope) async {
    final ScreenshotRequest request;
    try {
      request = ScreenshotRequest.fromJson(envelope.payload);
    } on ProtocolException catch (e) {
      appLog('cmd.screenshot inválido: $e');
      return;
    }
    void fail(String message) {
      appLog('Captura de tela falhou: $message');
      if (_disposed) return;
      connection.send(
        Envelope.create(
          MessageTypes.error,
          payload: ErrorPayload(
            ref: envelope.id,
            code: 'capture_failed',
            message: message,
          ).toJson(),
        ),
      );
    }

    final capturer = screenCapturer;
    if (capturer == null) return fail('Captura indisponível nesta TV.');
    final CapturedImage image;
    try {
      image = await capturer.capture(maxWidth: screenshotMaxWidth);
    } on Object catch (e) {
      return fail('Não foi possível capturar a tela (${e.runtimeType}).');
    }
    if (!screenshotMimes.contains(image.mime)) {
      return fail('Formato de imagem não suportado.');
    }
    if (image.bytes.length > maxScreenshotBytes) {
      return fail('Imagem grande demais.');
    }
    if (_disposed) return;
    connection.send(
      Envelope.create(
        MessageTypes.screenshotResult,
        payload: ScreenshotResult.fromBytes(
          requestId: request.requestId,
          mime: image.mime,
          bytes: image.bytes,
        ).toJson(),
      ),
    );
    appLog('Captura de tela enviada.');
  }

  Future<void> _onUnpair(Envelope envelope) async {
    _ack(envelope);
    await _unpairLocally();
  }

  /// A pedido do menu da TV: avisa o servidor (se responder em poucos
  /// segundos) e depois sempre apaga tudo e volta ao pareamento.
  Future<void> unpairSelf() async {
    final api = this.api;
    if (api != null) {
      final current = connection.credentials;
      try {
        await api.unpairSelf(current.server, current.deviceToken);
      } on Object catch (e) {
        appLog('Servidor não confirmou o desparear: ${e.runtimeType}');
      }
    }
    await _unpairLocally();
  }

  /// Apaga credenciais, manifesto salvo e cache; a TV sai do servidor.
  Future<void> _unpairLocally() async {
    _mediaRun++;
    try {
      await credentials?.clear();
    } on Object catch (e) {
      appLog('Falha ao apagar as credenciais: $e');
    }
    await _clearManifest();
    try {
      await cache?.clear();
    } on Object catch (e) {
      appLog('Falha ao apagar o cache de mídia: $e');
    }
    // Sai agora, sem esperar o 4401 que o servidor manda em seguida.
    connection.markUnauthorized();
  }

  void _ack(Envelope envelope) => connection.send(
        Envelope.create(
          MessageTypes.ack,
          payload: AckPayload(ref: envelope.id).toJson(),
        ),
      );

  @override
  void dispose() {
    _disposed = true;
    cache?.close();
    _identifyTimer?.cancel();
    _active.dispose();
    unawaited(_subscription?.cancel());
    connection.removeListener(_onConnectionChanged);
    super.dispose();
  }
}
