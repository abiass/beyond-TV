import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/media.dart';
import '../auth/auth_controller.dart';

/// Miniatura da mídia: a própria imagem, ou um ícone para vídeo e site.
class MediaThumb extends ConsumerWidget {
  const MediaThumb({required this.media, this.size = 56, super.key});

  final Media media;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icon = SizedBox.square(
      dimension: size,
      child: Icon(
        media.isVideo ? Icons.movie_outlined : Icons.public,
        size: size * 0.5,
      ),
    );
    if (!media.isImage) return icon;

    final url = ref.watch(apiClientProvider).fileUrl(media.id).toString();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => SizedBox.square(
          dimension: size,
          child: Icon(Icons.broken_image_outlined, size: size * 0.5),
        ),
      ),
    );
  }
}
