import 'dart:io';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_tv/src/content/manifest_store.dart';
import 'package:flutter_test/flutter_test.dart';

ContentManifest _manifest(String url) => ContentManifest(
      items: [
        ContentItem(
          mediaId: 'm1',
          kind: MediaKinds.url,
          name: 'Site',
          url: url,
        ),
      ],
    );

void main() {
  late Directory dir;
  late FileManifestStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('manifest_test');
    store = FileManifestStore(directory: () async => dir);
  });

  tearDown(() => dir.delete(recursive: true));

  test('sem arquivo devolve null', () async {
    expect(await store.load(), isNull);
  });

  test('salva e carrega', () async {
    final manifest = _manifest('https://example.local/a');
    await store.save(manifest);
    final loaded = await store.load();
    expect(loaded!.revision, manifest.revision);
    expect(loaded.items.single.url, 'https://example.local/a');
    expect(File('${dir.path}/manifest.json.tmp').existsSync(), isFalse);
  });

  test('arquivo corrompido devolve null e é apagado', () async {
    final file = File('${dir.path}/manifest.json');
    await file.writeAsString('{ isto não é json');
    expect(await store.load(), isNull);
    expect(file.existsSync(), isFalse);
  });

  test('clear apaga o manifesto', () async {
    await store.save(_manifest('https://example.local/a'));
    await store.clear();
    expect(await store.load(), isNull);
  });

  test('salva e carrega com agenda', () async {
    final manifest = ContentManifest(
      items: [
        const ContentItem(
          mediaId: 'm1',
          kind: MediaKinds.url,
          name: 'Site',
          url: 'https://example.local/a',
        ),
      ],
      schedules: [
        ScheduleRule(
          id: 'r1',
          days: {1, 2},
          startMinute: 8 * 60,
          endMinute: 9 * 60,
          priority: 3,
          target: ScheduleTargets.group,
          items: const [
            ContentItem(
              mediaId: 'm2',
              kind: MediaKinds.url,
              name: 'Manhã',
              url: 'https://example.local/b',
            ),
          ],
        ),
      ],
    );
    await store.save(manifest);
    final loaded = await store.load();
    expect(loaded!.revision, manifest.revision);
    final rule = loaded.schedules.single;
    expect(rule.id, 'r1');
    expect(rule.days, {1, 2});
    expect(rule.items.single.url, 'https://example.local/b');
    // Segunda-feira 08:30 cai na regra salva.
    expect(
      loaded.itemsAt(DateTime(2026, 10, 12, 8, 30)).single.mediaId,
      'm2',
    );
  });
}
