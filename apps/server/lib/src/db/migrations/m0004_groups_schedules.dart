import '../migrator.dart';

/// Conteúdo padrão dos grupos e agendamentos.
///
/// Grupo ganha `media_id` ou `playlist_id` (exclusivos, garantido pela
/// aplicação), como a TV. Um agendamento mira uma TV ou um grupo (nunca os
/// dois) e some junto com a playlist, a TV ou o grupo. `days` é um bitmask:
/// o bit `d - 1` liga o dia ISO `d` (segunda = bit 0, domingo = bit 6).
/// `start_min` e `end_min` são minutos desde a meia-noite, no relógio local
/// da TV.
const migration0004 = Migration(4, 'groups_schedules', r'''
ALTER TABLE groups ADD COLUMN media_id TEXT REFERENCES media (id) ON DELETE SET NULL;
ALTER TABLE groups ADD COLUMN playlist_id TEXT REFERENCES playlists (id) ON DELETE SET NULL;

CREATE TABLE schedules (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  playlist_id TEXT NOT NULL REFERENCES playlists (id) ON DELETE CASCADE,
  device_id   TEXT REFERENCES devices (id) ON DELETE CASCADE,
  group_id    INTEGER REFERENCES groups (id) ON DELETE CASCADE,
  days        INTEGER NOT NULL CHECK (days BETWEEN 1 AND 127),
  start_min   INTEGER NOT NULL CHECK (start_min BETWEEN 0 AND 1439),
  end_min     INTEGER NOT NULL CHECK (end_min BETWEEN 0 AND 1439),
  priority    INTEGER NOT NULL CHECK (priority BETWEEN 0 AND 100),
  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  CHECK ((device_id IS NULL) <> (group_id IS NULL))
) STRICT, WITHOUT ROWID;

CREATE INDEX schedules_device_id ON schedules (device_id);
CREATE INDEX schedules_group_id ON schedules (group_id);
CREATE INDEX schedules_playlist_id ON schedules (playlist_id);
''');
