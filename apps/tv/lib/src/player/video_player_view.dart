import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../remote/app_log.dart';

/// Superfície de vídeo mudo, sem controles e sem repetição.
abstract interface class VideoSurfaceController {
  /// Chamado uma vez quando o vídeo chega ao fim.
  set onCompleted(void Function() callback);

  Future<void> initialize();
  Future<void> play();

  /// Imagem do vídeo; só vale depois de [initialize].
  Widget buildView(BuildContext context);

  Future<void> dispose();
}

/// Cria a superfície de [file]; os testes trocam por um falso.
typedef VideoSurfaceFactory = VideoSurfaceController Function(File file);

/// Fábrica padrão: usa o plugin `video_player`.
VideoSurfaceController defaultVideoSurface(File file) =>
    PluginVideoSurface(file);

/// [VideoSurfaceController] sobre o `video_player`.
class PluginVideoSurface implements VideoSurfaceController {
  PluginVideoSurface(File file)
      : _controller = VideoPlayerController.file(file);

  final VideoPlayerController _controller;
  void Function()? _onCompleted;
  bool _done = false;

  @override
  set onCompleted(void Function() callback) => _onCompleted = callback;

  @override
  Future<void> initialize() async {
    await _controller.initialize();
    await _controller.setVolume(0);
    await _controller.setLooping(false);
    _controller.addListener(_check);
  }

  // Terminou: chegou ao fim da duração e parou.
  void _check() {
    final value = _controller.value;
    if (_done || !value.isInitialized) return;
    if (value.duration > Duration.zero &&
        value.position >= value.duration &&
        !value.isPlaying) {
      _done = true;
      _onCompleted?.call();
    }
  }

  @override
  Future<void> play() => _controller.play();

  @override
  Widget buildView(BuildContext context) => Center(
        child: AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: VideoPlayer(_controller),
        ),
      );

  @override
  Future<void> dispose() async {
    _controller.removeListener(_check);
    await _controller.dispose();
  }
}

/// Toca [file] uma vez e avisa [onCompleted] ao terminar. Se o vídeo não
/// abrir, avisa depois de [errorDelay] para a rotação seguir.
class VideoItemView extends StatefulWidget {
  const VideoItemView({
    super.key,
    required this.file,
    required this.onCompleted,
    this.factory = defaultVideoSurface,
    this.errorDelay = const Duration(seconds: 5),
  });

  final File file;
  final void Function() onCompleted;
  final VideoSurfaceFactory factory;
  final Duration errorDelay;

  @override
  State<VideoItemView> createState() => _VideoItemViewState();
}

class _VideoItemViewState extends State<VideoItemView> {
  late final VideoSurfaceController _surface;
  Timer? _errorTimer;
  bool _ready = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _surface = widget.factory(widget.file)..onCompleted = _complete;
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _surface.initialize();
      if (_disposed) return;
      setState(() => _ready = true);
      await _surface.play();
    } on Object catch (e) {
      appLog('Falha ao abrir o vídeo: $e');
      if (!_disposed) _errorTimer = Timer(widget.errorDelay, _complete);
    }
  }

  void _complete() {
    if (!_disposed) widget.onCompleted();
  }

  @override
  void dispose() {
    _disposed = true;
    _errorTimer?.cancel();
    unawaited(_surface.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: _ready ? _surface.buildView(context) : const SizedBox.expand(),
    );
  }
}
