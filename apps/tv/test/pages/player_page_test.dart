import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_tv/src/app.dart';
import 'package:beyond_tv/src/content/manifest_store.dart';
import 'package:beyond_tv/src/device/credentials.dart';
import 'package:beyond_tv/src/realtime/backoff.dart';
import 'package:beyond_tv/src/content/content_controller.dart';
import 'package:beyond_tv/src/pages/player_page.dart';
import 'package:beyond_tv/src/realtime/device_connection.dart';
import 'package:beyond_tv/src/player/video_player_view.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fake_socket.dart';
import '../support/fakes.dart';

const _saved = Credentials(
  deviceId: 'tv-1',
  deviceToken: 'segredo',
  server: pcSala,
);

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

Envelope _sync(String url) =>
    Envelope.create(MessageTypes.contentSync, payload: _site(url).toJson());

/// Vídeo falso: mostra `VIDEO:<nome>` e deixa o teste terminar o vídeo.
class _FakeVideo implements VideoSurfaceController {
  _FakeVideo(this.file);

  final File file;
  void Function()? completed;
  bool disposed = false;

  @override
  set onCompleted(void Function() callback) => completed = callback;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> play() async {}

  @override
  Widget buildView(BuildContext context) =>
      Text('VIDEO:${file.uri.pathSegments.last}');

  @override
  Future<void> dispose() async => disposed = true;
}

String _shaOf(String content) =>
    sha256.convert(utf8.encode(content)).toString();

ContentItem _image(String content, {int? seconds}) => ContentItem(
      mediaId: 'img-$content',
      kind: MediaKinds.image,
      name: 'Imagem $content',
      sha256: _shaOf(content),
      durationSeconds: seconds,
    );

ContentItem _video(String content, {int? seconds}) => ContentItem(
      mediaId: 'vid-$content',
      kind: MediaKinds.video,
      name: 'Vídeo $content',
      sha256: _shaOf(content),
      durationSeconds: seconds,
    );

Envelope _syncItems(List<ContentItem> items) => Envelope.create(
      MessageTypes.contentSync,
      payload: ContentManifest(items: items).toJson(),
    );

void main() {
  late Directory mediaDir;
  late List<_FakeVideo> videos;
  late FakeConnector connector;
  late MemoryCredentialStore credentials;
  late MemoryManifestStore manifests;
  late FakePlayerLog log;

  var clockNow = DateTime(2026, 10, 14, 7, 0);

  Future<void> open(WidgetTester tester) async {
    useTvScreen(tester);
    connector = FakeConnector();
    credentials = MemoryCredentialStore(_saved);
    manifests = MemoryManifestStore();
    log = FakePlayerLog();
    videos = [];
    await tester.pumpWidget(
      TvApp(
        mediaRoot: () async => mediaDir,
        // Download que nunca termina: sem timers pendentes no teste.
        mediaClient: () => MockClient(
          (_) => Completer<http.Response>().future,
        ),
        videoSurface: (file) {
          final video = _FakeVideo(file);
          videos.add(video);
          return video;
        },
        credentials: credentials,
        discovery: FakeDiscovery(),
        api: fakeApi(),
        connector: connector.call,
        backoffFactory: () => Backoff(initial: const Duration(hours: 1)),
        manifestStore: manifests,
        webPlayer: fakeWebPlayer(log),
        now: () => clockNow,
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  /// Entrega a mensagem do socket falso até a tela.
  Future<void> deliver(WidgetTester tester, Envelope envelope) async {
    connector.last.serverSend(envelope);
    await tester.pump();
    await tester.pump();
  }

  /// Põe um arquivo já baixado no cache.
  void cacheFile(String content) =>
      File('${mediaDir.path}/${_shaOf(content)}').writeAsStringSync(content);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  bool isCachedImage(Widget w, String content) =>
      w is Image &&
      w.image is FileImage &&
      (w.image as FileImage).file.path.endsWith(_shaOf(content));

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  setUp(() {
    mediaDir = Directory.systemTemp.createTempSync('player_page_media');
  });

  tearDown(() => mediaDir.deleteSync(recursive: true));

  testWidgets('manifesto vazio mostra "Aguardando conteúdo"', (tester) async {
    await open(tester);
    expect(find.textContaining('Aguardando conteúdo'), findsOneWidget);
    await close(tester);
  });

  testWidgets('content.sync abre o site e outro sync troca a URL', (
    tester,
  ) async {
    await open(tester);
    await deliver(tester, _sync('https://example.local/a'));
    expect(find.text('WEB:https://example.local/a'), findsOneWidget);
    expect(find.textContaining('Aguardando conteúdo'), findsNothing);

    await deliver(tester, _sync('https://example.local/b'));
    expect(find.text('WEB:https://example.local/b'), findsOneWidget);
    await close(tester);
  });

  testWidgets('cmd.reload recarrega o player e manda ack', (tester) async {
    await open(tester);
    await deliver(tester, _sync('https://example.local/a'));

    final reload = Envelope.create(MessageTypes.cmdReload);
    await deliver(tester, reload);
    expect(log.reloads, 1);
    final acks = connector.last.envelopes.where((e) => e.type == 'ack');
    expect(
      acks.map((e) => AckPayload.fromJson(e.payload).ref),
      contains(reload.id),
    );
    await close(tester);
  });

  testWidgets('cmd.identify mostra o nome e some depois da duração', (
    tester,
  ) async {
    await open(tester);
    await deliver(tester, _sync('https://example.local/a'));
    await deliver(
      tester,
      Envelope.create(
        MessageTypes.cmdIdentify,
        payload: const IdentifyPayload(name: 'Recepção', durationSeconds: 1)
            .toJson(),
      ),
    );
    expect(find.text('Recepção'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Recepção'), findsNothing);
    await close(tester);
  });

  testWidgets('cmd.unpair limpa tudo e volta à seleção de servidor', (
    tester,
  ) async {
    await open(tester);
    await deliver(tester, _sync('https://example.local/a'));
    expect(manifests.saved, isNotNull);

    await deliver(tester, Envelope.create(MessageTypes.cmdUnpair));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(credentials.saved, isNull);
    expect(manifests.saved, isNull);
    expect(find.text('Escolha o servidor'), findsOneWidget);
    expect(
      find.text('Esta TV foi removida do painel. Pareie de novo.'),
      findsOneWidget,
    );
    await close(tester);
  });

  testWidgets('wakelock liga no init e desliga no dispose', (tester) async {
    useTvScreen(tester);
    final connector = FakeConnector();
    final calls = <bool>[];
    final connection = DeviceConnection(
      credentials: _saved,
      deviceInfo: const FakeDeviceInfo(),
      store: MemoryCredentialStore(_saved),
      connector: connector.call,
      backoff: Backoff(initial: const Duration(hours: 1)),
    );
    final content = ContentController(
      store: MemoryManifestStore(),
      connection: connection,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          content: content,
          connection: connection,
          webPlayer: fakeWebPlayer(FakePlayerLog()),
          onUnauthorized: (_) {},
          setWakelock: (on) async => calls.add(on),
        ),
      ),
    );
    expect(calls, [true]);

    await tester.pumpWidget(const SizedBox());
    expect(calls, [true, false]);
  });

  testWidgets('imagem pronta aparece com Image.file', (tester) async {
    cacheFile('a');
    await open(tester);
    await deliver(tester, _syncItems([_image('a')]));
    await settle(tester);

    expect(
      find.byWidgetPredicate((w) => isCachedImage(w, 'a')),
      findsOneWidget,
    );
    expect(find.text('Baixando conteúdo…'), findsNothing);
    await close(tester);
  });

  testWidgets('sem arquivo pronto mostra "Baixando conteúdo…"', (tester) async {
    await open(tester);
    await deliver(tester, _syncItems([_image('a')]));
    await settle(tester);

    expect(find.text('Baixando conteúdo…'), findsOneWidget);
    expect(find.textContaining('Aguardando conteúdo'), findsNothing);
    await close(tester);
  });

  testWidgets('troca de item com o tempo, com fade', (tester) async {
    cacheFile('a');
    cacheFile('b');
    await open(tester);
    await deliver(
      tester,
      _syncItems([_image('a', seconds: 5), _image('b', seconds: 5)]),
    );
    await settle(tester);
    expect(
      find.byWidgetPredicate((w) => isCachedImage(w, 'a')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 5));
    // No meio da transição as duas imagens existem.
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byWidgetPredicate((w) => isCachedImage(w, 'a')),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate((w) => isCachedImage(w, 'b')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 1));
    expect(find.byWidgetPredicate((w) => isCachedImage(w, 'a')), findsNothing);
    expect(
      find.byWidgetPredicate((w) => isCachedImage(w, 'b')),
      findsOneWidget,
    );
    await close(tester);
  });

  testWidgets('vídeo avança ao completar', (tester) async {
    cacheFile('v');
    cacheFile('a');
    await open(tester);
    await deliver(tester, _syncItems([_video('v'), _image('a', seconds: 5)]));
    await settle(tester);

    expect(find.text('VIDEO:${_shaOf('v')}'), findsOneWidget);
    await tester.pump(const Duration(minutes: 5));
    expect(find.text('VIDEO:${_shaOf('v')}'), findsOneWidget);

    videos.single.completed!();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('VIDEO:${_shaOf('v')}'), findsNothing);
    expect(
      find.byWidgetPredicate((w) => isCachedImage(w, 'a')),
      findsOneWidget,
    );
    expect(videos.single.disposed, isTrue);
    await close(tester);
  });

  testWidgets('site e imagem alternam; site usa o WebView falso', (
    tester,
  ) async {
    cacheFile('a');
    await open(tester);
    await deliver(
      tester,
      _syncItems([
        const ContentItem(
          mediaId: 's',
          kind: MediaKinds.url,
          name: 'Site',
          url: 'https://example.local/s',
        ),
        _image('a'),
      ]),
    );
    await settle(tester);
    expect(find.text('WEB:https://example.local/s'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('WEB:https://example.local/s'), findsNothing);
    expect(
      find.byWidgetPredicate((w) => isCachedImage(w, 'a')),
      findsOneWidget,
    );
    await close(tester);
  });

  testWidgets('identify aparece por cima da imagem', (tester) async {
    cacheFile('a');
    await open(tester);
    await deliver(tester, _syncItems([_image('a')]));
    await settle(tester);
    await deliver(
      tester,
      Envelope.create(
        MessageTypes.cmdIdentify,
        payload: const IdentifyPayload(name: 'Recepção', durationSeconds: 1)
            .toJson(),
      ),
    );
    expect(find.text('Recepção'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => isCachedImage(w, 'a')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 1));
    await close(tester);
  });

  group('agenda', () {
    ContentItem site(String id) => ContentItem(
          mediaId: id,
          kind: MediaKinds.url,
          name: id,
          url: 'https://example.local/$id',
        );

    Envelope syncAgenda({List<ContentItem> padrao = const []}) =>
        Envelope.create(
          MessageTypes.contentSync,
          payload: ContentManifest(
            items: padrao,
            schedules: [
              ScheduleRule(
                id: 'r1',
                days: {1, 2, 3, 4, 5, 6, 7},
                startMinute: 8 * 60,
                endMinute: 9 * 60,
                priority: 0,
                target: ScheduleTargets.device,
                items: [site('faixa')],
              ),
            ],
          ).toJson(),
        );

    setUp(() => clockNow = DateTime(2026, 10, 14, 7, 0));

    testWidgets('na faixa mostra o item da regra e depois volta ao padrão', (
      tester,
    ) async {
      clockNow = DateTime(2026, 10, 14, 8, 30);
      await open(tester);
      await deliver(tester, syncAgenda(padrao: [site('padrao')]));
      expect(find.text('WEB:https://example.local/faixa'), findsOneWidget);

      // Sai da faixa: o relógio avança e o timer de minuto reavalia.
      clockNow = DateTime(2026, 10, 14, 9, 0, 1);
      await tester.pump(const Duration(minutes: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('WEB:https://example.local/padrao'), findsOneWidget);
      expect(find.text('WEB:https://example.local/faixa'), findsNothing);
      await close(tester);
    });

    testWidgets('fora da faixa e sem padrão mostra "Aguardando conteúdo"', (
      tester,
    ) async {
      await open(tester);
      await deliver(tester, syncAgenda());
      expect(find.textContaining('Aguardando conteúdo'), findsOneWidget);

      clockNow = DateTime(2026, 10, 14, 8, 30);
      await tester.pump(const Duration(minutes: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('WEB:https://example.local/faixa'), findsOneWidget);
      expect(find.textContaining('Aguardando conteúdo'), findsNothing);
      await close(tester);
    });
  });
}
