import 'package:fake_async/fake_async.dart';
import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_tv/src/player/playlist_rotation.dart';
import 'package:flutter_test/flutter_test.dart';

ContentItem _img(String id, {int? seconds}) => ContentItem(
      mediaId: id,
      kind: MediaKinds.image,
      name: id,
      sha256: 'a' * 64,
      durationSeconds: seconds,
    );

ContentItem _video(String id, {int? seconds}) => ContentItem(
      mediaId: id,
      kind: MediaKinds.video,
      name: id,
      sha256: 'b' * 64,
      durationSeconds: seconds,
    );

ContentItem _site(String id, {int? seconds}) => ContentItem(
      mediaId: id,
      kind: MediaKinds.url,
      name: id,
      url: 'https://example.local/$id',
      durationSeconds: seconds,
    );

void main() {
  late Set<String> ready;
  late PlaylistRotation rotation;

  PlaylistRotation make(List<ContentItem> items, {Set<String>? ids}) {
    ready = ids ?? {for (final i in items) i.mediaId};
    rotation = PlaylistRotation(isReady: (i) => ready.contains(i.mediaId))
      ..setItems(items);
    return rotation;
  }

  String? now() => rotation.current?.item.mediaId;

  test('cada item fica a sua duração', () {
    fakeAsync((async) {
      make([_img('a', seconds: 5), _img('b', seconds: 20)]);
      expect(now(), 'a');
      async.elapse(const Duration(seconds: 4));
      expect(now(), 'a');
      async.elapse(const Duration(seconds: 1));
      expect(now(), 'b');
      async.elapse(const Duration(seconds: 19));
      expect(now(), 'b');
      async.elapse(const Duration(seconds: 1));
      expect(now(), 'a');
      rotation.dispose();
    });
  });

  test('sem duração, com vários itens, usa 10 s', () {
    fakeAsync((async) {
      make([_img('a'), _site('b')]);
      async.elapse(const Duration(seconds: 9));
      expect(now(), 'a');
      async.elapse(const Duration(seconds: 1));
      expect(now(), 'b');
      rotation.dispose();
    });
  });

  test('item único sem duração fica parado', () {
    fakeAsync((async) {
      make([_site('a')]);
      async.elapse(const Duration(hours: 5));
      expect(now(), 'a');
      expect(async.pendingTimers, isEmpty);
      rotation.dispose();
    });
  });

  test('vídeo sem duração avança em onVideoCompleted', () {
    fakeAsync((async) {
      make([_video('v'), _img('a', seconds: 5)]);
      async.elapse(const Duration(minutes: 10));
      expect(now(), 'v');
      rotation.onVideoCompleted();
      expect(now(), 'a');
      // Fim de vídeo fora de hora é ignorado.
      rotation.onVideoCompleted();
      expect(now(), 'a');
      rotation.dispose();
    });
  });

  test('vídeo com duração avança pelo timer', () {
    fakeAsync((async) {
      make([_video('v', seconds: 30), _img('a', seconds: 5)]);
      async.elapse(const Duration(seconds: 30));
      expect(now(), 'a');
      rotation.dispose();
    });
  });

  test('vídeo sozinho recomeça ao terminar', () {
    fakeAsync((async) {
      make([_video('v')]);
      final before = rotation.current!.key;
      rotation.onVideoCompleted();
      expect(now(), 'v');
      expect(rotation.current!.key, isNot(before));
      rotation.dispose();
    });
  });

  test('pula itens que não estão prontos', () {
    fakeAsync((async) {
      make(
        [_img('a', seconds: 5), _img('b', seconds: 5), _img('c', seconds: 5)],
        ids: {'a', 'c'},
      );
      async.elapse(const Duration(seconds: 5));
      expect(now(), 'c');
      async.elapse(const Duration(seconds: 5));
      expect(now(), 'a');
      rotation.dispose();
    });
  });

  test('nada pronto: current é null, e começa quando o primeiro fica pronto',
      () {
    fakeAsync((async) {
      make([_img('a', seconds: 5), _img('b', seconds: 5)], ids: {});
      expect(rotation.current, isNull);
      ready.add('b');
      rotation.readinessChanged();
      expect(now(), 'b');
      // Outro item pronto não tira o atual da tela.
      ready.add('a');
      rotation.readinessChanged();
      expect(now(), 'b');
      rotation.dispose();
    });
  });

  test('item único que ganha companhia passa a rotacionar', () {
    fakeAsync((async) {
      make([_img('a'), _img('b')], ids: {'a'});
      async.elapse(const Duration(minutes: 1));
      expect(now(), 'a');
      ready.add('b');
      rotation.readinessChanged();
      async.elapse(const Duration(seconds: 10));
      expect(now(), 'b');
      rotation.dispose();
    });
  });

  test('novo manifesto recomeça do índice 0', () {
    fakeAsync((async) {
      make([_img('a', seconds: 5), _img('b', seconds: 5)]);
      async.elapse(const Duration(seconds: 5));
      expect(now(), 'b');
      ready.addAll(['x', 'y']);
      rotation.setItems([_img('x', seconds: 5), _img('y', seconds: 5)]);
      expect(now(), 'x');
      expect(rotation.current!.index, 0);
      async.elapse(const Duration(seconds: 5));
      expect(now(), 'y');
      rotation.dispose();
    });
  });

  test('dispose cancela os timers', () {
    fakeAsync((async) {
      make([_img('a', seconds: 5), _img('b', seconds: 5)]);
      expect(async.pendingTimers, isNotEmpty);
      rotation.dispose();
      expect(async.pendingTimers, isEmpty);
    });
  });
}
