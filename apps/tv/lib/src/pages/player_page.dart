import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:beyond_protocol/beyond_protocol.dart';

import '../content/content_controller.dart';
import '../player/image_player.dart';
import '../player/playlist_rotation.dart';
import '../player/video_player_view.dart';
import '../player/web_player.dart';
import '../realtime/device_connection.dart';
import '../remote/hidden_menu.dart';
import 'paired_page.dart';

/// Tela da TV pareada: o item da rotação em tela cheia (site, imagem ou
/// vídeo), ou o estado vazio enquanto não há conteúdo. Também leva de volta ao pareamento se a TV for removida.
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.content,
    required this.connection,
    required this.onUnauthorized,
    this.webPlayer = defaultWebPlayer,
    this.videoSurface = defaultVideoSurface,
    this.setWakelock = _defaultWakelock,
  });

  final ContentController content;
  final DeviceConnection connection;
  final WebPlayerBuilder webPlayer;
  final VideoSurfaceFactory videoSurface;

  /// Liga ou desliga o *wakelock*; os testes trocam por um registro.
  final Future<void> Function(bool on) setWakelock;

  /// Chamado quando esta TV foi removida; leva de volta ao pareamento.
  final void Function(BuildContext context) onUnauthorized;

  static Future<void> _defaultWakelock(bool on) =>
      on ? WakelockPlus.enable() : WakelockPlus.disable();

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final PlaylistRotation _rotation;
  late final _RestartController _restart;
  int? _version;
  Timer? _tick;
  bool _left = false;
  bool _immersive = false;
  int _maxCacheBytes = 0;

  // Teto do cache de imagens decodificadas: TVs baratas têm 1-2 GB de RAM.
  static const _imageCacheBytes = 64 << 20;

  // Troca de item com vídeo ou site de permeio é corte seco (sem fade):
  // assim nunca há dois decodificadores nem duas WebViews vivos. Cada corte
  // muda [_epoch], que recria o AnimatedSwitcher e descarta o item antigo.
  int _epoch = 0;
  RotationEntry? _shown;

  DeviceConnection get _connection => widget.connection;
  ContentController get _content => widget.content;

  @override
  void initState() {
    super.initState();
    final imageCache = PaintingBinding.instance.imageCache;
    _maxCacheBytes = imageCache.maximumSizeBytes;
    imageCache.maximumSizeBytes = _imageCacheBytes;
    unawaited(widget.setWakelock(true));
    _rotation = PlaylistRotation(isReady: _content.isReady)
      ..addListener(_onRotation);
    _restart = _RestartController(_rotation);
    _connection.addListener(_onChanged);
    _content.addListener(_onChanged);
    // Atualiza o "tentando de novo em N s" a cada segundo.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_connection.status == ConnectionStatus.offline && !_playing) {
        setState(() {});
      }
    });
    unawaited(_content.start());
    _connection.start();
  }

  bool get _playing => _content.activeItems.isNotEmpty;

  void _onRotation() {
    _content.reportShown(_rotation.current?.item);
    if (mounted) setState(() {});
  }

  void _onChanged() {
    if (!mounted) return;
    if (_connection.status == ConnectionStatus.unauthorized && !_left) {
      _left = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onUnauthorized(context);
      });
    }
    if (_content.activeVersion != _version) {
      _version = _content.activeVersion;
      _rotation.setItems(_content.activeItems);
    } else {
      _rotation.readinessChanged();
    }
    setState(() {});
  }

  void _trackEpoch(RotationEntry? current) {
    final previous = _shown;
    if (previous?.key == current?.key) return;
    _shown = current;
    if (previous == null || current == null) return;
    // Site -> site fica de fora: a mesma WebView segue com a nova URL.
    final bothSites = previous.item.kind == MediaKinds.url &&
        current.item.kind == MediaKinds.url;
    if (!bothSites && (_isHeavy(previous) || _isHeavy(current))) _epoch++;
  }

  bool _isHeavy(RotationEntry e) =>
      e.item.kind == MediaKinds.video || e.item.kind == MediaKinds.url;

  void _syncSystemUi() {
    if (_playing == _immersive) return;
    _immersive = _playing;
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        _immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    _connection.removeListener(_onChanged);
    _content.removeListener(_onChanged);
    _rotation.dispose();
    unawaited(widget.setWakelock(false));
    if (_immersive) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    _content.dispose();
    unawaited(_connection.dispose());
    PaintingBinding.instance.imageCache.maximumSizeBytes = _maxCacheBytes;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = _rotation.current;
    _syncSystemUi();
    _trackEpoch(current);

    final Widget body;
    if (!_playing) {
      _content.player = null;
      body = PairedPage(connection: _connection);
    } else {
      body = RepaintBoundary(
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSwitcher(
                key: ValueKey(_epoch),
                duration: const Duration(milliseconds: 600),
                child: current == null
                    ? const _DownloadingView(key: ValueKey('downloading'))
                    : KeyedSubtree(
                        // Sites seguidos compartilham a chave: a mesma WebView
                        // recebe a nova URL em vez de criar outra.
                        key: current.item.kind == MediaKinds.url
                            ? const ValueKey('web')
                            : ValueKey(current.key),
                        child: _itemView(context, current),
                      ),
              ),
              if (_connection.status == ConnectionStatus.offline)
                const Positioned(
                  top: 16,
                  right: 16,
                  child: Icon(Icons.circle, size: 12, color: Colors.orange),
                ),
            ],
          ),
        ),
      );
    }

    final name = _content.identifyName;
    return HiddenMenuHost(
      content: _content,
      connection: _connection,
      child: Stack(
        fit: StackFit.expand,
        children: [
          body,
          if (name != null)
            Positioned.fill(
              child: Container(
                color: const Color(0xCC000000),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(48),
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 120,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _itemView(BuildContext context, RotationEntry entry) {
    final item = entry.item;
    if (item.kind == MediaKinds.url) {
      return widget.webPlayer(
        context,
        item.url!,
        (controller) => _content.player = controller,
      );
    }
    _content.player = _restart;
    final file = _content.fileFor(item);
    if (file == null) return const SizedBox.expand();
    if (item.kind == MediaKinds.video) {
      return VideoItemView(
        file: file,
        factory: widget.videoSurface,
        onCompleted: _rotation.onVideoCompleted,
      );
    }
    return ImagePlayer(file: file);
  }
}

/// `cmd.reload` para imagem e vídeo: recomeça o item.
class _RestartController implements WebPlayerController {
  _RestartController(this.rotation);

  final PlaylistRotation rotation;

  @override
  Future<void> reload() async => rotation.restartCurrent();
}

/// Nada pronto ainda: os arquivos estão sendo baixados.
class _DownloadingView extends StatelessWidget {
  const _DownloadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Text(
          'Baixando conteúdo…',
          style: TextStyle(
            fontSize: 48,
            color: Colors.white,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
