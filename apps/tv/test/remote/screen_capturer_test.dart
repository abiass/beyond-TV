import 'package:beyond_tv/src/remote/screen_capturer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PlatformScreenCapturer.channelName);

  void mockChannel(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
  }

  test('usa o canal nativo: JPEG e maxWidth repassado', () async {
    final calls = <MethodCall>[];
    mockChannel((call) async {
      calls.add(call);
      return Uint8List.fromList([0xff, 0xd8, 0xff]);
    });

    final image = await PlatformScreenCapturer().capture(maxWidth: 1280);

    expect(image.mime, 'image/jpeg');
    expect(image.bytes, [0xff, 0xd8, 0xff]);
    expect(calls.single.method, 'capture');
    expect(calls.single.arguments, {'maxWidth': 1280});
  });

  testWidgets('canal com erro: usa a árvore do Flutter em PNG', (tester) async {
    mockChannel((call) async => throw PlatformException(code: 'unsupported'));
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: const ColoredBox(
          color: Colors.red,
          child: SizedBox(width: 200, height: 100),
        ),
      ),
    );

    final image = await tester.runAsync(
      () => PlatformScreenCapturer(boundaryKey: key).capture(maxWidth: 100),
    );

    expect(image!.mime, 'image/png');
    expect(image.bytes.sublist(1, 4), [0x50, 0x4e, 0x47]);
  });

  testWidgets('sem o lado nativo também cai no Flutter', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: const SizedBox(width: 50, height: 50)),
    );

    final image = await tester.runAsync(
      () => PlatformScreenCapturer(boundaryKey: key).capture(maxWidth: 1280),
    );

    expect(image!.mime, 'image/png');
  });

  test('sem canal nem árvore, lança', () async {
    expect(
      PlatformScreenCapturer().capture(maxWidth: 100),
      throwsA(isA<StateError>()),
    );
  });
}
