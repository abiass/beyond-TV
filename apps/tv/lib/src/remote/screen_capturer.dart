import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Imagem capturada da tela, pronta para ir ao servidor.
class CapturedImage {
  const CapturedImage({required this.bytes, required this.mime});

  final Uint8List bytes;
  final String mime;
}

/// Captura a tela da TV.
abstract interface class ScreenCapturer {
  /// Captura a tela com no máximo [maxWidth] pixels de largura.
  Future<CapturedImage> capture({required int maxWidth});
}

/// Usa o `PixelCopy` do Android (inclui WebView e vídeo). Se o canal nativo
/// falhar, captura a árvore do Flutter pelo [boundaryKey], que pode sair sem
/// o conteúdo de WebView e vídeo.
class PlatformScreenCapturer implements ScreenCapturer {
  PlatformScreenCapturer({MethodChannel? channel, this.boundaryKey})
      : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'beyond_tv/screenshot';

  final MethodChannel _channel;

  /// Chave do `RepaintBoundary` que envolve o app.
  final GlobalKey? boundaryKey;

  @override
  Future<CapturedImage> capture({required int maxWidth}) async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>(
        'capture',
        {'maxWidth': maxWidth},
      );
      if (bytes != null && bytes.isNotEmpty) {
        return CapturedImage(bytes: bytes, mime: 'image/jpeg');
      }
    } on MissingPluginException {
      // Sem o lado nativo: usa a árvore do Flutter.
    } on PlatformException {
      // PixelCopy indisponível ou falhou: usa a árvore do Flutter.
    }
    return _captureFlutter(maxWidth);
  }

  Future<CapturedImage> _captureFlutter(int maxWidth) async {
    final context = boundaryKey?.currentContext;
    final boundary = context?.findRenderObject();
    if (context == null || boundary is! RenderRepaintBoundary) {
      throw StateError('Árvore do Flutter indisponível para captura');
    }
    final deviceRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final ratio = math.min(maxWidth / boundary.size.width, deviceRatio);
    final ui.Image image = await boundary.toImage(pixelRatio: ratio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Falha ao codificar a imagem');
      return CapturedImage(
        bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        mime: 'image/png',
      );
    } finally {
      image.dispose();
    }
  }
}
