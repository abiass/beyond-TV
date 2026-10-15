import '../migrator.dart';

/// Biblioteca de mídia e conteúdo das TVs.
///
/// Na fase 6 só existem mídias `url`; imagem e vídeo (campos `sha256`,
/// `size_bytes` e `mime`) chegam na fase 7. `devices.media_id` guarda o site
/// exibido pela TV e vira playlist padrão na fase 7. Apagar a mídia deixa o
/// campo nulo (`ON DELETE SET NULL`).
const migration0002 = Migration(2, 'media', r'''
CREATE TABLE media (
  id         TEXT PRIMARY KEY,
  kind       TEXT NOT NULL CHECK (kind IN ('url', 'image', 'video')),
  name       TEXT NOT NULL,
  url        TEXT,
  sha256     TEXT,
  size_bytes INTEGER,
  mime       TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  CHECK (kind <> 'url' OR url IS NOT NULL)
) STRICT, WITHOUT ROWID;

CREATE INDEX media_url ON media (url);

-- Conteúdo da TV na fase 6 (um site). Na fase 7 vira playlist padrão.
ALTER TABLE devices ADD COLUMN media_id TEXT REFERENCES media (id) ON DELETE SET NULL;
CREATE INDEX devices_media_id ON devices (media_id);
''');
