import 'dart:io';

import 'package:beyond_server/server.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

const _m1 = Migration(1, 'cria a', 'CREATE TABLE a (id INTEGER PRIMARY KEY);');
const _m2 = Migration(
  2,
  'cria b',
  'CREATE TABLE b (id INTEGER PRIMARY KEY); INSERT INTO b VALUES (1);',
);

List<String> _tables(Database db) => db
    .select("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
    .map((row) => row['name'] as String)
    .toList();

void main() {
  late Database db;

  setUp(() => db = sqlite3.openInMemory());
  tearDown(() => db.close());

  test('aplica as migrações em ordem e grava a versão', () {
    expect(migrate(db, const [_m1, _m2]), [1, 2]);

    expect(db.userVersion, 2);
    expect(_tables(db), ['a', 'b']);
  });

  test('é idempotente', () {
    migrate(db, const [_m1, _m2]);

    expect(migrate(db, const [_m1, _m2]), isEmpty);
    expect(db.select('SELECT COUNT(*) AS n FROM b').single['n'], 1);
  });

  test('aplica só as novas migrações', () {
    migrate(db, const [_m1]);

    expect(migrate(db, const [_m1, _m2]), [2]);
    expect(db.userVersion, 2);
  });

  test('desfaz a migração que falhou e mantém a versão anterior', () {
    const broken = Migration(
      2,
      'quebrada',
      'CREATE TABLE c (id INTEGER); INSERT INTO nao_existe VALUES (1);',
    );

    expect(
      () => migrate(db, const [_m1, broken]),
      throwsA(
        isA<MigrationException>().having(
          (e) => e.message,
          'message',
          contains('quebrada'),
        ),
      ),
    );
    expect(db.userVersion, 1);
    expect(_tables(db), ['a']);
  });

  test('recusa banco mais novo que o servidor', () {
    db.userVersion = 3;

    expect(
      () => migrate(db, const [_m1, _m2]),
      throwsA(isA<MigrationException>()),
    );
  });

  test('recusa lista de migrações fora de ordem', () {
    expect(
      () => migrate(db, const [_m2, _m1]),
      throwsA(isA<MigrationException>()),
    );
    expect(db.userVersion, 0);
  });

  test('migrações 2 a 4 preservam TVs e grupos existentes', () {
    migrate(db, migrations.take(1).toList());
    db.execute(
      "INSERT INTO devices (id, name, token_hash) VALUES ('tv1', 'TV', 'h')",
    );
    db.execute("INSERT INTO groups (name) VALUES ('G')");

    expect(migrate(db, migrations), [2, 3, 4]);

    final row = db
        .select('SELECT name, media_id, playlist_id FROM devices')
        .single;
    expect(row['name'], 'TV');
    expect(row['media_id'], isNull);
    expect(row['playlist_id'], isNull);
    final group = db.select('SELECT name, media_id, playlist_id FROM groups');
    expect(group.single['name'], 'G');
    expect(group.single['media_id'], isNull);
    expect(group.single['playlist_id'], isNull);
  });

  group('openDatabase', () {
    late Directory dir;

    setUp(() async => dir = await Directory.systemTemp.createTemp('beyond_'));
    tearDown(() => dir.delete(recursive: true));

    test('cria o arquivo, ativa chaves estrangeiras e WAL', () {
      final path = p.join(dir.path, databaseFileName);
      final fileDb = openDatabase(path);
      addTearDown(fileDb.close);

      expect(File(path).existsSync(), isTrue);
      expect(fileDb.userVersion, migrations.length);
      expect(fileDb.select('PRAGMA foreign_keys').single.values.single, 1);
      expect(fileDb.select('PRAGMA journal_mode').single.values.single, 'wal');
    });
  });
}
