import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_server/server.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late Database db;
  late MediaStore store;

  setUp(() {
    db = openDatabase();
    store = MediaStore(db);
  });
  tearDown(() => db.close());

  test('cria com nome padrão igual ao host e encontra por id e URL', () {
    final media = store.createUrl(url: 'https://example.local/painel');

    expect(media.name, 'example.local');
    expect(media.kind, MediaKinds.url);
    expect(store.find(media.id)?.url, 'https://example.local/painel');
    expect(store.findByUrl('https://example.local/painel')?.id, media.id);
    expect(store.findByUrl('https://outro.local'), isNull);
    expect(store.find('nada'), isNull);
  });

  test('lista, atualiza e apaga', () {
    final a = store.createUrl(url: 'https://a.local', name: 'A');
    store.createUrl(url: 'https://b.local', name: 'B');

    expect(store.list(), hasLength(2));
    final updated = store.update(a.id, name: 'Novo', url: 'https://c.local')!;
    expect(updated.name, 'Novo');
    expect(updated.url, 'https://c.local');
    expect(store.update('nada', name: 'x'), isNull);
    expect(store.delete(a.id), isTrue);
    expect(store.delete(a.id), isFalse);
    expect(store.list(), hasLength(1));
  });

  test('toJson e toContentItem', () {
    final media = store.createUrl(url: 'https://a.local', name: 'A');

    expect(media.toJson()['url'], 'https://a.local');
    expect(media.toContentItem().mediaId, media.id);
  });

  test('apagar a mídia deixa devices.media_id nulo', () {
    final devices = DeviceStore(db);
    devices.create(
      id: 'tv1',
      name: 'TV',
      tokenHash: 'h',
      info: const DeviceInfo(appVersion: '0.5.0'),
    );
    final media = store.createUrl(url: 'https://a.local');
    expect(devices.setMedia('tv1', media.id), isTrue);
    expect(devices.devicesShowing(media.id), ['tv1']);

    store.delete(media.id);

    expect(devices.find('tv1')!.mediaId, isNull);
    expect(devices.setMedia('nada', null), isFalse);
  });
}
