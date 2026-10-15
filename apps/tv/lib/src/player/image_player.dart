import 'dart:io';

import 'package:flutter/material.dart';

/// Imagem em tela cheia, inteira (sem cortar), sobre fundo preto.
class ImagePlayer extends StatelessWidget {
  const ImagePlayer({super.key, required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Image.file(
        file,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const SizedBox.expand(),
      ),
    );
  }
}
