import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_server/server.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late Database db;
  late GroupStore store;
  late DeviceStore devices;

  setUp(() {
    db = openDatabase();
    store = GroupStore(db);
    devices = DeviceStore(db);
  });
  tearDown(() => db.close());

  String tv(String id) {
    devices.create(
      id: id,
      name: 'TV $id',
      tokenHash: 'hash-$id',
      info: const DeviceInfo(appVersion: '0.5.0'),
    );
    return id;
  }

  test('cria, encontra e renomeia', () {
    final g = store.create('Recepção');

    expect(g.deviceIds, isEmpty);
    expect(g.mediaId, isNull);
    expect(store.find(g.id)?.name, 'Recepção');
    expect(store.rename(g.id, 'Hall'), isTrue);
    expect(store.find(g.id)?.name, 'Hall');
    expect(store.rename(999, 'x'), isFalse);
    expect(store.find(999), isNull);
  });

  test('lista por nome, sem diferenciar maiúsculas, com os membros', () {
    final b = store.create('b');
    store.create('A');
    store.setMembers(b.id, [tv('tv1')]);

    final list = store.list();

    expect([for (final g in list) g.name], ['A', 'b']);
    expect(list.last.deviceIds, ['tv1']);
  });

  test('nome repetido com outra caixa é recusado pelo banco', () {
    store.create('Recepcao');

    expect(() => store.create('RECEPCAO'), throwsA(isA<SqliteException>()));
    expect(store.nameTaken('recepcao'), isTrue);
    expect(store.nameTaken('Outro'), isFalse);
  });

  test('nameTaken ignora o próprio grupo', () {
    final g = store.create('Hall');

    expect(store.nameTaken('hall', exceptId: g.id), isFalse);
    expect(store.nameTaken('hall'), isTrue);
  });

  test('setMembers move TVs entre grupos e tira as que saíram', () {
    final a = store.create('A');
    final b = store.create('B');
    tv('tv1');
    tv('tv2');
    tv('tv3');
    store.setMembers(a.id, ['tv1', 'tv2']);

    final changed = store.setMembers(b.id, ['tv2', 'tv3']);

    expect(changed, {'tv2', 'tv3'});
    expect(store.memberIds(a.id), ['tv1']);
    expect(store.memberIds(b.id), ['tv2', 'tv3']);

    final removed = store.setMembers(b.id, ['tv3']);
    expect(removed, {'tv2'});
    expect(devices.find('tv2')?.groupId, isNull);
  });

  test('setMembers com TV desconhecida não altera nada', () {
    final g = store.create('A');
    tv('tv1');
    store.setMembers(g.id, ['tv1']);

    expect(
      () => store.setMembers(g.id, ['tv1', 'nada']),
      throwsA(isA<ArgumentError>()),
    );
    expect(store.memberIds(g.id), ['tv1']);
  });

  test('setContent grava mídia ou playlist e limpa', () {
    final media = MediaStore(db).createUrl(url: 'https://a.local', name: 'A');
    final playlist = PlaylistStore(db, MediaStore(db)).create('P');
    final g = store.create('A');

    expect(store.setContent(g.id, mediaId: media.id), isTrue);
    expect(store.find(g.id)?.mediaId, media.id);

    store.setContent(g.id, playlistId: playlist.id);
    expect(store.find(g.id)?.mediaId, isNull);
    expect(store.find(g.id)?.playlistId, playlist.id);

    store.setContent(g.id);
    expect(store.find(g.id)?.playlistId, isNull);
    expect(store.setContent(999), isFalse);
  });

  test('apagar o grupo solta as TVs', () {
    final g = store.create('A');
    tv('tv1');
    store.setMembers(g.id, ['tv1']);

    expect(store.delete(g.id), isTrue);

    expect(devices.find('tv1')?.groupId, isNull);
    expect(store.delete(g.id), isFalse);
  });
}
