import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('isSafeContentUrl', () {
    test('aceita http e https com host', () {
      expect(isSafeContentUrl('https://example.local/painel?x=1'), isTrue);
      expect(isSafeContentUrl('http://192.168.0.10:3000/d/abc'), isTrue);
    });

    test('recusa outros esquemas, espaços e URLs longas demais', () {
      for (final url in [
        'file:///sdcard/a.html',
        'javascript:alert(1)',
        'data:text/html,oi',
        'https://',
        'example.local',
        'https://exa mple.local',
        '',
        'https://example.local/${'a' * maxContentUrlLength}',
      ]) {
        expect(isSafeContentUrl(url), isFalse, reason: url);
      }
    });
  });

  group('ContentManifest', () {
    const site = ContentItem(
      mediaId: 'm1',
      kind: MediaKinds.url,
      name: 'Vendas',
      url: 'https://example.local/vendas',
    );

    test('faz ida e volta por JSON mantendo a revisão', () {
      final manifest = ContentManifest(items: const [site]);

      final decoded = ContentManifest.fromJson(manifest.toJson());

      expect(decoded.revision, manifest.revision);
      expect(decoded.items.single.url, site.url);
    });

    test('a revisão muda quando o conteúdo muda', () {
      final a = ContentManifest(items: const [site]);
      final b = ContentManifest(
        items: const [
          ContentItem(
            mediaId: 'm1',
            kind: MediaKinds.url,
            name: 'Vendas',
            url: 'https://example.local/outro',
          ),
        ],
      );

      expect(a.revision, isNot(b.revision));
      expect(ContentManifest.empty.isEmpty, isTrue);
      expect(ContentManifest.empty.revision, isNot(a.revision));
    });
  });

  test('IdentifyPayload usa 10 s por padrão', () {
    final payload = IdentifyPayload.fromJson({'name': 'Recepção'});

    expect(payload.durationSeconds, 10);
    expect(payload.toJson(), {'name': 'Recepção', 'durationSeconds': 10});
  });

  test('AckPayload faz ida e volta', () {
    expect(AckPayload.fromJson(const AckPayload(ref: 'x').toJson()).ref, 'x');
  });

  test('DeviceSummary carrega o conteúdo atribuído', () {
    final summary = DeviceSummary(
      id: 'abc',
      name: 'Recepção',
      online: false,
      createdAt: DateTime.utc(2026, 10, 15),
      content: const ContentItem(
        mediaId: 'm1',
        kind: MediaKinds.url,
        name: 'Vendas',
        url: 'https://example.local/vendas',
      ),
    );

    final decoded = DeviceSummary.fromJson(summary.toJson());

    expect(decoded.content?.url, 'https://example.local/vendas');
    expect(
      DeviceSummary.fromJson({...summary.toJson(), 'content': null}).content,
      isNull,
    );
  });
}
