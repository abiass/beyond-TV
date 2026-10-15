import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_server/server.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late Database db;
  late MediaStore media;
  late PlaylistStore store;

  setUp(() {
    db = openDatabase();
    media = MediaStore(db);
    store = PlaylistStore(db, media);
  });
  tearDown(() => db.close());

  String site(String name) =>
      media.createUrl(url: 'https://$name.local', name: name).id;

  test('cria, encontra e renomeia', () {
    final p = store.create('Manhã');

    expect(p.itemCount, 0);
    expect(store.find(p.id)?.name, 'Manhã');
    expect(store.rename(p.id, 'Tarde'), isTrue);
    expect(store.find(p.id)?.name, 'Tarde');
    expect(store.rename('nada', 'x'), isFalse);
    expect(store.find('nada'), isNull);
  });

  test('lista por nome com a contagem de itens', () {
    final b = store.create('b');
    store.create('A');
    store.replaceItems(b.id, [(site('x'), null), (site('y'), 10)]);

    final list = store.list();

    expect([for (final p in list) p.name], ['A', 'b']);
    expect([for (final p in list) p.itemCount], [0, 2]);
  });

  test('replaceItems preserva a ordem e permite duplicados', () {
    final p = store.create('P');
    final a = site('a');
    final b = site('b');

    store.replaceItems(p.id, [(b, 15), (a, null), (b, null)]);

    final items = store.itemsOf(p.id);
    expect([for (final i in items) i.media.id], [b, a, b]);
    expect([for (final i in items) i.durationSeconds], [15, null, null]);

    store.replaceItems(p.id, [(a, 5)]);
    expect(store.itemsOf(p.id), hasLength(1));
    expect(store.find(p.id)?.itemCount, 1);
  });

  test('replaceItems é atômico', () {
    final p = store.create('P');
    final a = site('a');
    store.replaceItems(p.id, [(a, null)]);

    expect(
      () => store.replaceItems(p.id, [(a, null), ('nada', null)]),
      throwsA(isA<SqliteException>()),
    );

    expect(store.itemsOf(p.id), hasLength(1));
  });

  test('apagar a mídia a remove das playlists', () {
    final p = store.create('P');
    final a = site('a');
    final b = site('b');
    store.replaceItems(p.id, [(a, null), (b, null)]);

    expect(store.playlistsContaining(a), [p.id]);
    media.delete(a);

    expect([for (final i in store.itemsOf(p.id)) i.media.id], [b]);
    expect(store.playlistsContaining(a), isEmpty);
  });

  test('apagar a playlist zera as TVs que a exibiam', () {
    final devices = DeviceStore(db);
    devices.create(
      id: 'tv1',
      name: 'TV',
      tokenHash: 'h',
      info: const DeviceInfo(appVersion: '0.7.0'),
    );
    final p = store.create('P');
    devices.setContent('tv1', playlistId: p.id);
    expect(devices.devicesShowingPlaylist(p.id), ['tv1']);

    expect(store.delete(p.id), isTrue);

    expect(devices.find('tv1')?.playlistId, isNull);
    expect(store.delete(p.id), isFalse);
  });

  test('setContent grava um e zera o outro', () {
    final devices = DeviceStore(db);
    devices.create(
      id: 'tv1',
      name: 'TV',
      tokenHash: 'h',
      info: const DeviceInfo(appVersion: '0.7.0'),
    );
    final p = store.create('P');
    final a = site('a');

    devices.setContent('tv1', mediaId: a);
    expect(devices.find('tv1')?.mediaId, a);

    devices.setContent('tv1', playlistId: p.id);
    expect(devices.find('tv1')?.mediaId, isNull);
    expect(devices.find('tv1')?.playlistId, p.id);

    devices.setContent('tv1');
    expect(devices.find('tv1')?.playlistId, isNull);
    expect(devices.setContent('nada'), isFalse);
  });
}
