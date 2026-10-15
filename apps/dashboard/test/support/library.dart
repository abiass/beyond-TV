import 'package:beyond_dashboard/src/api/media.dart';
import 'package:beyond_protocol/beyond_protocol.dart';

/// Uma imagem, um vídeo e um site, como a biblioteca devolve.
List<Media> sampleMedia() => [
      Media(
        id: 'img',
        kind: MediaKinds.image,
        name: 'Promoção',
        sha256: 'a' * 64,
        sizeBytes: 183422,
        mime: 'image/png',
        createdAt: DateTime.utc(2026, 10, 3),
      ),
      Media(
        id: 'vid',
        kind: MediaKinds.video,
        name: 'Institucional',
        sha256: 'b' * 64,
        sizeBytes: 13000000,
        mime: 'video/mp4',
        createdAt: DateTime.utc(2026, 10, 2),
      ),
      Media(
        id: 'site',
        kind: MediaKinds.url,
        name: 'Painel',
        url: 'https://example.local/painel',
        createdAt: DateTime.utc(2026, 10, 1),
      ),
    ];
