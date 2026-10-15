import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_tv/src/content/content_controller.dart';
import 'package:beyond_tv/src/content/manifest_store.dart';
import 'package:beyond_tv/src/device/credentials.dart';
import 'package:beyond_tv/src/media/media_cache.dart';
import 'package:beyond_tv/src/realtime/backoff.dart';
import 'package:beyond_tv/src/realtime/device_connection.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fake_socket.dart';
import '../support/fakes.dart';

const _credentials = Credentials(
  deviceId: 'tv-1',
  deviceToken: 'segredo',
  server: pcSala,
);

Future<void> _wait([int ms = 40]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

ContentManifest _site(String url) => ContentManifest(
      items: [
        ContentItem(
          mediaId: 'm1',
          kind: MediaKinds.url,
          name: 'Site',
          url: url,
        ),
      ],
    );

Envelope _sync(ContentManifest manifest) =>
    Envelope.create(MessageTypes.contentSync, payload: manifest.toJson());

void main() {
  late FakeConnector connector;
  late MemoryManifestStore store;
  late DeviceConnection connection;
  late ContentController controller;

  Future<void> setUpController([
    ContentManifest? saved,
    MediaCache? cache,
    DateTime Function()? now,
  ]) async {
    connector = FakeConnector();
    store = MemoryManifestStore(saved);
    connection = DeviceConnection(
      credentials: _credentials,
      deviceInfo: const FakeDeviceInfo(),
      store: MemoryCredentialStore(_credentials),
      connector: connector.call,
      backoff: Backoff(
        initial: const Duration(milliseconds: 10),
        max: const Duration(milliseconds: 20),
        random: Random(1),
      ),
      heartbeatEvery: const Duration(milliseconds: 20),
      currentItem: () => controller.currentUrl,
    );
    controller = ContentController(
      store: store,
      connection: connection,
      cache: cache,
      now: now,
    );
    await controller.start();
    connection.start();
    await _wait();
  }

  tearDown(() async {
    controller.dispose();
    await connection.dispose();
  });

  List<Envelope> acks() => connector.last.envelopes
      .where((e) => e.type == MessageTypes.ack)
      .toList();

  test('começa com o manifesto salvo', () async {
    await setUpController(_site('https://example.local/salvo'));
    expect(controller.currentUrl, 'https://example.local/salvo');
    final hello = HelloPayload.fromJson(connector.last.envelopes.first.payload);
    expect(hello.currentItem, 'https://example.local/salvo');
  });

  test('content.sync novo salva, notifica e manda ack', () async {
    await setUpController();
    var notified = 0;
    controller.addListener(() => notified++);
    final envelope = _sync(_site('https://example.local/a'));
    connector.last.serverSend(envelope);
    await _wait();

    expect(controller.currentUrl, 'https://example.local/a');
    expect(store.saved!.revision, controller.manifest.revision);
    expect(notified, 1);
    expect(AckPayload.fromJson(acks().single.payload).ref, envelope.id);
  });

  test('mesma revision só manda ack', () async {
    await setUpController(_site('https://example.local/a'));
    var notified = 0;
    controller.addListener(() => notified++);
    final envelope = _sync(_site('https://example.local/a'));
    connector.last.serverSend(envelope);
    await _wait();

    expect(notified, 0);
    expect(AckPayload.fromJson(acks().single.payload).ref, envelope.id);
  });

  test('descarta item com javascript:', () async {
    await setUpController();
    connector.last.serverSend(_sync(_site('javascript:alert(1)')));
    await _wait();

    expect(controller.currentUrl, isNull);
    expect(controller.manifest.items, isEmpty);
  });

  test('manifesto inválido é ignorado', () async {
    await setUpController();
    connector.last.serverSend(
      Envelope.create(MessageTypes.contentSync, payload: {'x': 1}),
    );
    await _wait();
    expect(controller.manifest.isEmpty, isTrue);
    expect(acks(), isEmpty);
  });

  test('currentItem do heartbeat é a URL exibida', () async {
    await setUpController();
    connector.last.serverSend(_sync(_site('https://example.local/a')));
    await _wait(80);

    final beats = connector.last.envelopes
        .where((e) => e.type == MessageTypes.heartbeat)
        .map((e) => HeartbeatPayload.fromJson(e.payload));
    expect(beats.last.currentItem, 'https://example.local/a');
  });

  test('4401 apaga o manifesto salvo', () async {
    await setUpController(_site('https://example.local/a'));
    connector.last.serverClose(WsCloseCodes.unauthorized);
    await _wait();
    expect(store.saved, isNull);
  });

  test('descarta imagem e vídeo com sha256 inválido', () async {
    await setUpController();
    ContentItem media(String id, String kind, String sha) => ContentItem(
          mediaId: id,
          kind: kind,
          name: id,
          sha256: sha,
        );
    connector.last.serverSend(
      _sync(
        ContentManifest(
          items: [
            media('ok', MediaKinds.image, 'a' * 64),
            media('ruim1', MediaKinds.image, '../x'),
            media('ruim2', MediaKinds.video, 'A' * 64),
            const ContentItem(
              mediaId: 'sem',
              kind: MediaKinds.image,
              name: 's',
            ),
          ],
        ),
      ),
    );
    await _wait();
    expect([for (final i in controller.manifest.items) i.mediaId], ['ok']);
  });

  group('agenda', () {
    ScheduleRule rule(String id, List<ContentItem> items) => ScheduleRule(
          id: id,
          days: {1, 2, 3, 4, 5, 6, 7},
          startMinute: 8 * 60,
          endMinute: 9 * 60,
          priority: 0,
          target: ScheduleTargets.device,
          items: items,
        );

    test('descarta itens inseguros dentro das regras', () async {
      await setUpController();
      connector.last.serverSend(
        _sync(
          ContentManifest(
            items: const [
              ContentItem(
                mediaId: 'p',
                kind: MediaKinds.url,
                name: 'p',
                url: 'https://example.local/p',
              ),
            ],
            schedules: [
              rule('r1', [
                const ContentItem(
                  mediaId: 'ok',
                  kind: MediaKinds.url,
                  name: 'ok',
                  url: 'https://example.local/ok',
                ),
                const ContentItem(
                  mediaId: 'js',
                  kind: MediaKinds.url,
                  name: 'js',
                  url: 'javascript:alert(1)',
                ),
                const ContentItem(
                  mediaId: 'sha',
                  kind: MediaKinds.image,
                  name: 'sha',
                  sha256: '../x',
                ),
              ]),
            ],
          ),
        ),
      );
      await _wait();
      final rules = controller.manifest.schedules;
      expect(rules.single.id, 'r1');
      expect([for (final i in rules.single.items) i.mediaId], ['ok']);
      expect(store.saved!.schedules.single.items, hasLength(1));
    });

    test('o controlador segue a faixa pelo relógio injetado', () async {
      var now = DateTime(2026, 10, 14, 7, 0);
      final manifest = ContentManifest(
        items: const [
          ContentItem(
            mediaId: 'p',
            kind: MediaKinds.url,
            name: 'p',
            url: 'https://example.local/p',
          ),
        ],
        schedules: [
          rule('r1', const [
            ContentItem(
              mediaId: 'a',
              kind: MediaKinds.url,
              name: 'a',
              url: 'https://example.local/a',
            ),
          ]),
        ],
      );
      await setUpController(manifest, null, () => now);
      expect(controller.currentUrl, 'https://example.local/p');
      now = DateTime(2026, 10, 14, 8, 30);
      await controller.start();
      expect(controller.currentUrl, 'https://example.local/a');
    });

    test('baixa e preserva os arquivos de todos os horários', () async {
      final dir = await Directory.systemTemp.createTemp('ctrl_cache');
      addTearDown(() => dir.delete(recursive: true));
      String shaOf(String c) => sha256.convert(utf8.encode(c)).toString();
      ContentItem image(String c) => ContentItem(
            mediaId: 'img-$c',
            kind: MediaKinds.image,
            name: c,
            sha256: shaOf(c),
          );
      final requested = <String>[];
      final cache = MediaCache(
        root: dir,
        client: MockClient((request) async {
          requested.add(request.url.path);
          final content =
              RegExp(r'img-(\w+)').firstMatch(request.url.path)![1]!;
          return http.Response.bytes(utf8.encode(content), 200);
        }),
      );
      // Arquivo velho que ninguém usa deve ser podado.
      File('${dir.path}/${'f' * 64}').writeAsStringSync('velho');
      await setUpController(
        ContentManifest(
          items: [image('padrao')],
          schedules: [
            rule('r1', [image('agendada')]),
          ],
        ),
        cache,
        () => DateTime(2026, 10, 14, 7, 0),
      );
      await _wait(200);

      expect(requested, hasLength(2));
      expect(File('${dir.path}/${shaOf('padrao')}').existsSync(), isTrue);
      expect(File('${dir.path}/${shaOf('agendada')}').existsSync(), isTrue);
      expect(File('${dir.path}/${'f' * 64}').existsSync(), isFalse);
      expect(controller.isReady(image('agendada')), isTrue);
    });
  });
}
