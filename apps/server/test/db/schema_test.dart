import 'package:beyond_server/server.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late Database db;

  setUp(() => db = openDatabase());
  tearDown(() => db.close());

  void insertAdmin() => db.execute(
    "INSERT INTO admins (id, username, password_hash) VALUES (1, 'admin', 'x')",
  );

  void insertDevice(String id, {int? groupId, String tokenHash = 'h1'}) =>
      db.execute(
        'INSERT INTO devices (id, name, token_hash, group_id) '
        'VALUES (?, ?, ?, ?)',
        [id, 'TV $id', tokenHash, groupId],
      );

  test('cria as tabelas do esquema inicial', () {
    final tables = db
        .select(
          "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
        )
        .map((row) => row['name'])
        .toList();

    expect(tables, [
      'admins',
      'devices',
      'groups',
      'media',
      'playlist_items',
      'playlists',
      'schedules',
      'sessions',
      'settings',
    ]);
  });

  test('gera um server_id aleatório de 32 caracteres hex', () {
    final rows = db.select(
      "SELECT value FROM settings WHERE key = 'server_id'",
    );
    final serverId = rows.single['value'] as String;

    expect(serverId, matches(RegExp(r'^[0-9a-f]{32}$')));

    final other = openDatabase();
    addTearDown(other.close);
    expect(
      other.select('SELECT value FROM settings').single['value'],
      isNot(serverId),
    );
  });

  test('preenche created_at em UTC ISO 8601', () {
    insertAdmin();

    final createdAt =
        db.select('SELECT created_at FROM admins').single['created_at']
            as String;
    expect(DateTime.parse(createdAt).isUtc, isTrue);
  });

  test('username do admin é único sem diferenciar maiúsculas', () {
    insertAdmin();

    expect(
      () => db.execute(
        "INSERT INTO admins (username, password_hash) VALUES ('ADMIN', 'y')",
      ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('remover o admin remove as sessões dele', () {
    insertAdmin();
    db.execute(
      'INSERT INTO sessions (id_hash, admin_id, expires_at) '
      "VALUES ('s1', 1, '2099-01-01T00:00:00.000Z')",
    );

    db.execute('DELETE FROM admins WHERE id = 1');

    expect(db.select('SELECT * FROM sessions'), isEmpty);
  });

  test('sessão exige admin existente', () {
    expect(
      () => db.execute(
        'INSERT INTO sessions (id_hash, admin_id, expires_at) '
        "VALUES ('s1', 99, '2099-01-01T00:00:00.000Z')",
      ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('remover o grupo deixa as TVs sem grupo', () {
    db.execute("INSERT INTO groups (id, name) VALUES (1, 'Recepção')");
    insertDevice('tv1', groupId: 1);

    db.execute('DELETE FROM groups WHERE id = 1');

    expect(
      db.select('SELECT group_id FROM devices').single['group_id'],
      isNull,
    );
  });

  test('token_hash é único', () {
    insertDevice('tv1');

    expect(() => insertDevice('tv2'), throwsA(isA<SqliteException>()));
  });

  test('info da TV precisa ser JSON válido', () {
    insertDevice('tv1');

    expect(
      () => db.execute("UPDATE devices SET info = 'nao é json'"),
      throwsA(isA<SqliteException>()),
    );
  });

  group('playlists', () {
    void insertMedia(String id) => db.execute(
      "INSERT INTO media (id, kind, name, url) VALUES (?, 'url', 'M', 'https://a.local')",
      [id],
    );

    void insertPlaylist(String id) =>
        db.execute("INSERT INTO playlists (id, name) VALUES (?, 'P')", [id]);

    void insertItem(String playlistId, int position, String mediaId) =>
        db.execute(
          'INSERT INTO playlist_items (playlist_id, position, media_id) '
          'VALUES (?, ?, ?)',
          [playlistId, position, mediaId],
        );

    test('está na versão 4', () {
      expect(db.userVersion, 4);
    });

    test('apagar a mídia remove os itens das playlists', () {
      insertMedia('m1');
      insertPlaylist('p1');
      insertItem('p1', 0, 'm1');

      db.execute("DELETE FROM media WHERE id = 'm1'");

      expect(db.select('SELECT * FROM playlist_items'), isEmpty);
      expect(db.select('SELECT * FROM playlists'), hasLength(1));
    });

    test('apagar a playlist remove os itens e zera as TVs', () {
      insertMedia('m1');
      insertPlaylist('p1');
      insertItem('p1', 0, 'm1');
      insertDevice('tv1');
      db.execute("UPDATE devices SET playlist_id = 'p1'");

      db.execute("DELETE FROM playlists WHERE id = 'p1'");

      expect(db.select('SELECT * FROM playlist_items'), isEmpty);
      expect(
        db.select('SELECT playlist_id FROM devices').single['playlist_id'],
        isNull,
      );
    });

    test('a posição é única na playlist, mas a mídia pode repetir', () {
      insertMedia('m1');
      insertPlaylist('p1');
      insertItem('p1', 0, 'm1');
      insertItem('p1', 1, 'm1');

      expect(() => insertItem('p1', 1, 'm1'), throwsA(isA<SqliteException>()));
    });

    test('item exige playlist e mídia existentes', () {
      insertPlaylist('p1');

      expect(
        () => insertItem('p1', 0, 'nada'),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => insertItem('nada', 0, 'nada'),
        throwsA(isA<SqliteException>()),
      );
    });
  });
  group('grupos e agendamentos', () {
    void insertPlaylist(String id) =>
        db.execute("INSERT INTO playlists (id, name) VALUES (?, 'P')", [id]);
    void insertGroup(int id) =>
        db.execute("INSERT INTO groups (id, name) VALUES (?, 'G$id')", [id]);
    void insertSchedule(
      String id, {
      String? deviceId,
      int? groupId,
      int days = 31,
      int start = 660,
      int end = 840,
      int priority = 10,
      String playlistId = 'p1',
    }) => db.execute(
      'INSERT INTO schedules (id, name, playlist_id, device_id, group_id, '
      "days, start_min, end_min, priority) VALUES (?, 'S', ?, ?, ?, ?, ?, ?, ?)",
      [id, playlistId, deviceId, groupId, days, start, end, priority],
    );

    test('está na versão 4', () {
      expect(db.userVersion, 4);
    });

    test('exige exatamente um alvo', () {
      insertPlaylist('p1');
      insertGroup(1);
      insertDevice('tv1');

      insertSchedule('a', deviceId: 'tv1');
      insertSchedule('b', groupId: 1);
      expect(() => insertSchedule('c'), throwsA(isA<SqliteException>()));
      expect(
        () => insertSchedule('d', deviceId: 'tv1', groupId: 1),
        throwsA(isA<SqliteException>()),
      );
    });

    test('valida os limites de dias, horários e prioridade', () {
      insertPlaylist('p1');
      insertGroup(1);

      for (final bad in [
        () => insertSchedule('a', groupId: 1, days: 0),
        () => insertSchedule('b', groupId: 1, days: 128),
        () => insertSchedule('c', groupId: 1, start: 1440),
        () => insertSchedule('d', groupId: 1, end: -1),
        () => insertSchedule('e', groupId: 1, priority: 101),
        () => insertSchedule('f', groupId: 1, priority: -1),
      ]) {
        expect(bad, throwsA(isA<SqliteException>()));
      }
      insertSchedule('ok', groupId: 1, days: 127, start: 1439, end: 0);
    });

    test('apagar a playlist apaga os agendamentos dela', () {
      insertPlaylist('p1');
      insertGroup(1);
      insertSchedule('a', groupId: 1);

      db.execute("DELETE FROM playlists WHERE id = 'p1'");

      expect(db.select('SELECT * FROM schedules'), isEmpty);
    });

    test('apagar a TV apaga os agendamentos dela', () {
      insertPlaylist('p1');
      insertDevice('tv1');
      insertDevice('tv2', tokenHash: 'h2');
      insertSchedule('a', deviceId: 'tv1');
      insertSchedule('b', deviceId: 'tv2');

      db.execute("DELETE FROM devices WHERE id = 'tv1'");

      expect(db.select('SELECT id FROM schedules').single['id'], 'b');
    });

    test('apagar o grupo apaga os agendamentos e solta as TVs', () {
      insertPlaylist('p1');
      insertGroup(1);
      insertDevice('tv1', groupId: 1);
      insertSchedule('a', groupId: 1);

      db.execute('DELETE FROM groups WHERE id = 1');

      expect(db.select('SELECT * FROM schedules'), isEmpty);
      expect(
        db.select('SELECT group_id FROM devices').single['group_id'],
        isNull,
      );
    });

    test('apagar a playlist ou a mídia zera o conteúdo do grupo', () {
      insertPlaylist('p1');
      db.execute(
        "INSERT INTO media (id, kind, name, url) VALUES ('m1', 'url', 'M', 'https://a.local')",
      );
      insertGroup(1);
      insertGroup(2);
      db.execute("UPDATE groups SET playlist_id = 'p1' WHERE id = 1");
      db.execute("UPDATE groups SET media_id = 'm1' WHERE id = 2");

      db.execute("DELETE FROM playlists WHERE id = 'p1'");
      db.execute("DELETE FROM media WHERE id = 'm1'");

      for (final row in db.select('SELECT media_id, playlist_id FROM groups')) {
        expect(row['media_id'], isNull);
        expect(row['playlist_id'], isNull);
      }
    });
  });
}
