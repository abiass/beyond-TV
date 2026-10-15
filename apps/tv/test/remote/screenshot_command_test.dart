import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_tv/src/content/content_controller.dart';
import 'package:beyond_tv/src/content/manifest_store.dart';
import 'package:beyond_tv/src/device/credentials.dart';
import 'package:beyond_tv/src/realtime/backoff.dart';
import 'package:beyond_tv/src/realtime/device_connection.dart';
import 'package:beyond_tv/src/remote/screen_capturer.dart';
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

void main() {
  late FakeConnector connector;
  late DeviceConnection connection;
  late ContentController controller;

  Future<void> setUpController(FakeScreenCapturer? capturer) async {
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
      screenCapturer: capturer,
    );
    await controller.start();
    connection.start();
    await _wait();
  }

  tearDown(() async {
    controller.dispose();
    await connection.dispose();
  });

  Envelope request([String requestId = 'req-1']) => Envelope.create(
        MessageTypes.cmdScreenshot,
        payload: ScreenshotRequest(requestId: requestId).toJson(),
      );

  List<Envelope> sent(String type) =>
      connector.last.envelopes.where((e) => e.type == type).toList();

  test('responde com screenshot.result e o base64 da imagem', () async {
    final bytes = Uint8List.fromList([0xff, 0xd8, 1, 2, 3]);
    final capturer = FakeScreenCapturer(
      image: CapturedImage(bytes: bytes, mime: 'image/jpeg'),
    );
    await setUpController(capturer);

    connector.last.serverSend(request());
    await _wait();

    final results = sent(MessageTypes.screenshotResult);
    expect(results, hasLength(1));
    expect(results.single.payload, {
      'requestId': 'req-1',
      'mime': 'image/jpeg',
      'data': base64Encode(bytes),
    });
    expect(capturer.widths, [screenshotMaxWidth]);
    expect(sent(MessageTypes.error), isEmpty);
  });

  test('falha na captura responde error com a ref do envelope', () async {
    await setUpController(FakeScreenCapturer(error: StateError('boom')));
    final envelope = request();

    connector.last.serverSend(envelope);
    await _wait();

    final errors = sent(MessageTypes.error);
    expect(errors, hasLength(1));
    final payload = ErrorPayload.fromJson(errors.single.payload);
    expect(payload.ref, envelope.id);
    expect(payload.code, 'capture_failed');
    expect(sent(MessageTypes.screenshotResult), isEmpty);
  });

  test('sem capturador responde capture_failed', () async {
    await setUpController(null);
    final envelope = request();

    connector.last.serverSend(envelope);
    await _wait();

    final payload =
        ErrorPayload.fromJson(sent(MessageTypes.error).single.payload);
    expect(payload.ref, envelope.id);
    expect(payload.code, 'capture_failed');
  });

  test('imagem maior que o limite responde error', () async {
    await setUpController(
      FakeScreenCapturer(
        image: CapturedImage(
          bytes: Uint8List(maxScreenshotBytes + 1),
          mime: 'image/jpeg',
        ),
      ),
    );
    final envelope = request();

    connector.last.serverSend(envelope);
    await _wait();

    expect(sent(MessageTypes.screenshotResult), isEmpty);
    final payload =
        ErrorPayload.fromJson(sent(MessageTypes.error).single.payload);
    expect(payload.ref, envelope.id);
    expect(payload.code, 'capture_failed');
  });

  test('payload inválido não envia nada nem captura', () async {
    final capturer = FakeScreenCapturer(
      image: CapturedImage(bytes: Uint8List(3), mime: 'image/jpeg'),
    );
    await setUpController(capturer);

    connector.last.serverSend(
      Envelope.create(MessageTypes.cmdScreenshot, payload: {'x': 1}),
    );
    await _wait();

    expect(capturer.widths, isEmpty);
    expect(sent(MessageTypes.screenshotResult), isEmpty);
    expect(sent(MessageTypes.error), isEmpty);
  });
}
