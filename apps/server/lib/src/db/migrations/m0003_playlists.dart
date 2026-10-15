import '../migrator.dart';

/// Playlists e o conteúdo das TVs por playlist.
///
/// `playlist_items.position` vai de 0 a n-1 e a mesma mídia pode aparecer
/// mais de uma vez. Apagar a mídia remove os itens (`CASCADE`); apagar a
/// playlist deixa `devices.playlist_id` nulo (`SET NULL`). Uma TV exibe
/// `media_id` ou `playlist_id`, nunca os dois (garantido pela aplicação).
const migration0003 = Migration(3, 'playlists', r'''
CREATE TABLE playlists (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
) STRICT, WITHOUT ROWID;

CREATE TABLE playlist_items (
  playlist_id TEXT NOT NULL REFERENCES playlists (id) ON DELETE CASCADE,
  position    INTEGER NOT NULL,
  media_id    TEXT NOT NULL REFERENCES media (id) ON DELETE CASCADE,
  duration_s  INTEGER,
  PRIMARY KEY (playlist_id, position)
) STRICT, WITHOUT ROWID;

CREATE INDEX playlist_items_media_id ON playlist_items (media_id);

ALTER TABLE devices ADD COLUMN playlist_id TEXT REFERENCES playlists (id) ON DELETE SET NULL;
CREATE INDEX devices_playlist_id ON devices (playlist_id);
''');
