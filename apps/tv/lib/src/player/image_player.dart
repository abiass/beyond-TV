import 'dart:io';

import 'package:flutter/material.dart';

/// Imagem em tela cheia, inteira (sem cortar), sobre fundo preto.
///
/// Decodifica no tamanho da tela (px físicos), nunca maior, para não gastar
/// RAM com imagens de até 25 MiB; ao sair, tira a imagem do `imageCache`.
class ImagePlayer extends StatefulWidget {
  const ImagePlayer({super.key, required this.file});

  final File file;

  @override
  State<ImagePlayer> createState() => _ImagePlayerState();
}

class _ImagePlayerState extends State<ImagePlayer> {
  ImageProvider? _provider;

  @override
  void dispose() {
    _provider?.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // `fit` mantém a proporção dentro da caixa da tela.
    final provider = ResizeImage(
      FileImage(widget.file),
      width: (size.width * dpr).round(),
      height: (size.height * dpr).round(),
      policy: ResizeImagePolicy.fit,
    );
    _provider = provider;
    return ColoredBox(
      color: Colors.black,
      child: Image(
        image: provider,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const SizedBox.expand(),
      ),
    );
  }
}
