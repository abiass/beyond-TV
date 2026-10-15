import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:test/test.dart';

void main() {
  RemoteInput roundTrip(RemoteInput input) =>
      RemoteInput.fromJson(input.toJson());

  test('toque, tecla, texto e rolagem fazem ida e volta', () {
    final tap = roundTrip(const RemoteInput.tap(0.25, 0.75));
    expect(tap.kind, RemoteInputKind.tap);
    expect((tap.x, tap.y), (0.25, 0.75));

    expect(roundTrip(const RemoteInput.key(RemoteKeys.enter)).key, 'enter');
    expect(roundTrip(const RemoteInput.text('ção@1')).text, 'ção@1');

    final scroll = roundTrip(const RemoteInput.scroll(-0.5, x: 0.1, y: 0.2));
    expect((scroll.dy, scroll.x, scroll.y), (-0.5, 0.1, 0.2));
  });

  test('aceita coordenadas inteiras (0 e 1) vindas do JSON', () {
    final tap = RemoteInput.fromJson({'kind': 'tap', 'x': 0, 'y': 1});

    expect((tap.x, tap.y), (0.0, 1.0));
  });

  group('recusa', () {
    final invalid = <String, Map<String, Object?>>{
      'tipo desconhecido': {'kind': 'swipe'},
      'toque fora da tela': {'kind': 'tap', 'x': 1.2, 'y': 0.5},
      'toque sem y': {'kind': 'tap', 'x': 0.5},
      'tecla desconhecida': {'kind': 'key', 'key': 'f13'},
      'texto vazio': {'kind': 'text', 'text': ''},
      'texto longo': {'kind': 'text', 'text': 'a' * (maxRemoteTextLength + 1)},
      'rolagem exagerada': {'kind': 'scroll', 'dy': 50, 'x': 0.5, 'y': 0.5},
    };
    for (final MapEntry(:key, :value) in invalid.entries) {
      test(key, () {
        expect(
          () => RemoteInput.fromJson(value),
          throwsA(isA<ProtocolException>()),
        );
      });
    }
  });

  test('toString não mostra o texto digitado', () {
    expect(
      const RemoteInput.text('senha-secreta').toString(),
      isNot(contains('senha')),
    );
  });

  test('ScreenshotRequest leva o maxWidth só quando pedido', () {
    expect(const ScreenshotRequest(requestId: 'r').toJson(), {
      'requestId': 'r',
    });
    final live = ScreenshotRequest.fromJson(
      const ScreenshotRequest(requestId: 'r', maxWidth: 960).toJson(),
    );
    expect(live.maxWidth, 960);
  });
}
