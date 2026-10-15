import 'dart:math';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_tv/src/content/content_controller.dart';
import 'package:beyond_tv/src/content/manifest_store.dart';
import 'package:beyond_tv/src/device/credentials.dart';
import 'package:beyond_tv/src/player/web_player.dart';
import 'package:beyond_tv/src/realtime/backoff.dart';
import 'package:beyond_tv/src/realtime/device_connection.dart';
import 'package:beyond_tv/src/remote/remote_input.dart';
import 'package:beyond_tv/src/remote/screen_capturer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';
import '../support/fakes.dart';

const _credentials = Credentials(
  deviceId: 'tv-1',
  deviceToken: 'segredo',
  server: pcSala,
);

Future<void> _wait([int ms = 40]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

/// Player de site falso que registra as entradas.
class _FakeSitePlayer implements WebPlayerController, RemoteInputTarget {
  final inputs = <RemoteInput>[];
  RemoteInputException? failure;

  @override
  Future<void> reload() async {}

  @override
  Future<void> input(RemoteInput input) async {
    if (failure case final failure?) throw failure;
    inputs.add(input);
  }
}

/// Player de imagem/vídeo: não aceita controle remoto.
class _FakeMediaPlayer implements WebPlayerController {
  @override
  Future<void> reload() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cmd.input', () {
    late FakeConnector connector;
    late DeviceConnection connection;
    late ContentController controller;

    setUp(() async {
      connector = FakeConnector();
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
        heartbeatEvery: const Duration(minutes: 5),
      );
      controller = ContentController(
        store: MemoryManifestStore(),
        connection: connection,
        screenCapturer: FakeScreenCapturer(
          image: CapturedImage(
            bytes: Uint8List.fromList([0xff, 0xd8, 1]),
            mime: 'image/jpeg',
          ),
        ),
      );
      await controller.start();
      connection.start();
      await _wait();
    });

    tearDown(() async {
      controller.dispose();
      await connection.dispose();
    });

    Envelope inputEnvelope(RemoteInput input) =>
        Envelope.create(MessageTypes.cmdInput, payload: input.toJson());

    List<Envelope> sent(String type) =>
        connector.last.envelopes.where((e) => e.type == type).toList();

    test('repassa ao site e responde ack', () async {
      final player = _FakeSitePlayer();
      controller.player = player;

      final envelope = inputEnvelope(const RemoteInput.tap(0.5, 0.5));
      connector.last.serverSend(envelope);
      await _wait();

      expect(player.inputs.single.kind, RemoteInputKind.tap);
      final ack = AckPayload.fromJson(sent(MessageTypes.ack).last.payload);
      expect(ack.ref, envelope.id);
    });

    test('sem site na tela responde no_web_content', () async {
      controller.player = _FakeMediaPlayer();

      connector.last.serverSend(
        inputEnvelope(const RemoteInput.key(RemoteKeys.enter)),
      );
      await _wait();

      final error =
          ErrorPayload.fromJson(sent(MessageTypes.error).single.payload);
      expect(error.code, 'no_web_content');
    });

    test('falha no site responde input_failed com a mensagem', () async {
      controller.player = _FakeSitePlayer()
        ..failure = const RemoteInputException('Clique no campo primeiro.');

      connector.last.serverSend(inputEnvelope(const RemoteInput.text('a')));
      await _wait();

      final error =
          ErrorPayload.fromJson(sent(MessageTypes.error).single.payload);
      expect(error.code, 'input_failed');
      expect(error.message, 'Clique no campo primeiro.');
    });

    test('quadro ao vivo usa a largura pedida', () async {
      final capturer = FakeScreenCapturer(
        image: CapturedImage(
          bytes: Uint8List.fromList([0xff, 0xd8, 1]),
          mime: 'image/jpeg',
        ),
      );
      controller.dispose();
      controller = ContentController(
        store: MemoryManifestStore(),
        connection: connection,
        screenCapturer: capturer,
      );
      await controller.start();

      connector.last.serverSend(
        Envelope.create(
          MessageTypes.cmdScreenshot,
          payload: const ScreenshotRequest(
            requestId: 'r',
            maxWidth: liveFrameMaxWidth,
          ).toJson(),
        ),
      );
      await _wait();

      expect(capturer.widths, [liveFrameMaxWidth]);
    });
  });

  group('RemoteInputDriver', () {
    const channel = MethodChannel(RemoteInputDriver.channelName);
    late List<MethodCall> calls;
    late List<String> scripts;
    late Object scriptResult;

    setUp(() {
      calls = [];
      scripts = [];
      scriptResult = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    RemoteInputDriver driver() => RemoteInputDriver(
          webViewId: 7,
          runJavaScript: (script) async {
            scripts.add(script);
            return scriptResult;
          },
        );

    test('toque, tecla e rolagem vão para o lado nativo', () async {
      await driver().send(const RemoteInput.tap(0.1, 0.9));
      await driver().send(const RemoteInput.key(RemoteKeys.tab));
      await driver().send(const RemoteInput.scroll(1, x: 0.5, y: 0.4));

      expect([for (final c in calls) c.method], ['tap', 'key', 'scroll']);
      expect(calls[0].arguments, {'webViewId': 7, 'x': 0.1, 'y': 0.9});
      expect(calls[1].arguments, {'webViewId': 7, 'key': 'tab'});
      expect(
        calls[2].arguments,
        {'webViewId': 7, 'x': 0.5, 'y': 0.4, 'dy': 1.0},
      );
      expect(scripts, isEmpty);
    });

    test('texto entra pelo JavaScript, escapado', () async {
      await driver().send(const RemoteInput.text('a"b\\c\nção'));

      expect(calls, isEmpty);
      expect(scripts.single, contains(r'"a\"b\\c\nção"'));
    });

    test('sem campo com foco avisa para clicar no campo', () async {
      scriptResult = false;

      expect(
        () => driver().send(const RemoteInput.text('oi')),
        throwsA(
          isA<RemoteInputException>().having(
            (e) => e.message,
            'message',
            contains('Clique no campo'),
          ),
        ),
      );
    });

    test('erro nativo vira RemoteInputException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(
          code: 'no_webview',
          message: 'O site ainda não está na tela.',
        );
      });

      expect(
        () => driver().send(const RemoteInput.tap(0.5, 0.5)),
        throwsA(isA<RemoteInputException>()),
      );
    });
  });
}
