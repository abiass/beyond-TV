import 'dart:convert';
import 'dart:typed_data';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_server/server.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/realtime_support.dart';
import '../support/test_server.dart';

/// JPEG de mentira: só a assinatura e o enchimento.
Uint8List fakeJpeg([int length = 64]) => Uint8List.fromList([
  0xFF, 0xD8, 0xFF, 0xE0, //
  ...List.generate(length - 4, (i) => i % 251),
]);

void main() {
  late FakeClock clock;
  late TestServer server;
  late Map<String, String> admin;
  late ({String id, String token}) tv;

  setUp(() async {
    clock = FakeClock();
    server = await TestServer.start(clock: clock.call);
    admin = await setupAdmin(server);
    tv = insertDevice(server);
  });

  Future<http.Response> request({String? id}) => server.post(
    '/api/v1/devices/${id ?? tv.id}/commands',
    json: {'type': 'screenshot'},
    headers: admin,
  );

  Future<http.Response> fetch({String? id}) =>
      server.get('/api/v1/devices/${id ?? tv.id}/screenshot', headers: admin);

  Future<(Inbox, dynamic)> connectTv([
    ({String id, String token})? device,
  ]) async {
    final d = device ?? tv;
    final channel = await connectDevice(server, d.token);
    final inbox = Inbox(channel);
    sendHello(channel);
    await inbox.nextOfType(MessageTypes.contentSync);
    return (inbox, channel);
  }

  Envelope result(String requestId, List<int> bytes, {String? mime}) =>
      Envelope.create(
        MessageTypes.screenshotResult,
        payload: ScreenshotResult(
          requestId: requestId,
          mime: mime ?? 'image/jpeg',
          data: base64Encode(bytes),
        ).toJson(),
      );

  Future<String> ask(Inbox inbox) async {
    expect((await request()).statusCode, 202);
    final cmd = await inbox.nextOfType(MessageTypes.cmdScreenshot);
    return ScreenshotRequest.fromJson(cmd.payload).requestId;
  }

  /// Dá tempo ao servidor para processar o que a TV mandou.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 150));

  test('fluxo completo: pedido, resultado, evento e download', () async {
    final (inbox, channel) = await connectTv();
    final adminInbox = Inbox(await connectAdmin(server, admin));

    final response = await request();
    expect(response.statusCode, 202);
    final requestId = (jsonBody(response)! as Map)['requestId'] as String;
    final cmd = await inbox.nextOfType(MessageTypes.cmdScreenshot);
    expect(ScreenshotRequest.fromJson(cmd.payload).requestId, requestId);

    final jpeg = fakeJpeg();
    channel.sink.add(result(requestId, jpeg).encode());

    final event = await adminInbox.nextOfType(MessageTypes.deviceScreenshot);
    final parsed = DeviceScreenshotEvent.fromJson(event.payload);
    expect(parsed.deviceId, tv.id);
    expect(parsed.capturedAt, clock.now);

    final image = await fetch();
    expect(image.statusCode, 200);
    expect(image.bodyBytes, jpeg);
    expect(image.headers['content-type'], 'image/jpeg');
    expect(image.headers['cache-control'], 'no-store');
    expect(image.headers['x-content-type-options'], 'nosniff');
    expect(image.headers['x-captured-at'], clock.now.toIso8601String());
  });

  test('GET exige admin e responde 404 sem captura', () async {
    final none = await fetch();
    expect(none.statusCode, 404);
    expect(errorCode(none), 'no_screenshot');
    expect((await fetch(id: 'nada')).statusCode, 404);
    final anon = await server.get('/api/v1/devices/${tv.id}/screenshot');
    expect(anon.statusCode, 401);
  });

  test('TV offline responde 409 e não conta para o intervalo', () async {
    final r = await request();
    expect(r.statusCode, 409);
    expect(errorCode(r), 'device_offline');

    await connectTv();
    expect((await request()).statusCode, 202);
  });

  test('intervalo de 5 s entre pedidos da mesma TV', () async {
    await connectTv();
    expect((await request()).statusCode, 202);

    final limited = await request();
    expect(limited.statusCode, 429);
    expect(errorCode(limited), 'too_many_requests');
    expect(limited.headers['retry-after'], isNotNull);

    clock.advance(screenshotCooldown);
    expect((await request()).statusCode, 202);
  });

  test('requestId desconhecido, de outra TV ou expirado é ignorado', () async {
    final (inbox, channel) = await connectTv();
    final other = insertDevice(server, name: 'Salão');
    final (_, otherChannel) = await connectTv(other);
    final adminInbox = Inbox(await connectAdmin(server, admin));

    final requestId = await ask(inbox);
    channel.sink.add(result('desconhecido', fakeJpeg()).encode());
    otherChannel.sink.add(result(requestId, fakeJpeg()).encode());
    await settle();
    expect((await fetch()).statusCode, 404);
    expect((await fetch(id: other.id)).statusCode, 404);

    clock.advance(ScreenshotStore.pendingTtl);
    channel.sink.add(result(requestId, fakeJpeg()).encode());
    await settle();
    expect((await fetch()).statusCode, 404);

    // A TV segue conectada e um pedido novo funciona.
    clock.advance(screenshotCooldown);
    final fresh = await ask(inbox);
    channel.sink.add(result(fresh, fakeJpeg()).encode());
    await adminInbox.nextOfType(MessageTypes.deviceScreenshot);
    expect((await fetch()).statusCode, 200);
  });

  test('conteúdo inválido é descartado', () async {
    final (inbox, channel) = await connectTv();
    final requestId = await ask(inbox);
    final png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3];

    Envelope raw(String mime, String data) => Envelope.create(
      MessageTypes.screenshotResult,
      payload: {'requestId': requestId, 'mime': mime, 'data': data},
    );

    channel.sink
      ..add(result(requestId, fakeJpeg(), mime: 'image/gif').encode())
      ..add(result(requestId, png).encode()) // PNG declarado como JPEG
      ..add(raw('image/jpeg', '@@não é base64@@').encode())
      ..add(result(requestId, <int>[]).encode())
      ..add(result(requestId, fakeJpeg(maxScreenshotBytes + 1)).encode())
      ..add(
        Envelope.create(
          MessageTypes.screenshotResult,
          payload: {'requestId': requestId},
        ).encode(),
      );
    await settle();
    expect((await fetch()).statusCode, 404);

    // O pedido segue pendente: um resultado correto ainda é aceito.
    channel.sink.add(result(requestId, fakeJpeg()).encode());
    await settle();
    expect((await fetch()).statusCode, 200);
  });

  test('resultado só vale uma vez', () async {
    final (inbox, channel) = await connectTv();
    final adminInbox = Inbox(await connectAdmin(server, admin));
    final requestId = await ask(inbox);

    channel.sink.add(result(requestId, fakeJpeg(32)).encode());
    await adminInbox.nextOfType(MessageTypes.deviceScreenshot);
    channel.sink.add(result(requestId, fakeJpeg(48)).encode());
    await settle();

    expect((await fetch()).bodyBytes, hasLength(32));
  });

  test('error da TV remove o pedido pendente', () async {
    final (inbox, channel) = await connectTv();
    expect((await request()).statusCode, 202);
    final cmd = await inbox.nextOfType(MessageTypes.cmdScreenshot);
    final requestId = ScreenshotRequest.fromJson(cmd.payload).requestId;

    channel.sink.add(
      Envelope.create(
        MessageTypes.error,
        payload: ErrorPayload(
          ref: cmd.id,
          code: 'capture_failed',
          message: 'sem janela',
        ).toJson(),
      ).encode(),
    );
    await settle();
    channel.sink.add(result(requestId, fakeJpeg()).encode());
    await settle();

    expect((await fetch()).statusCode, 404);
  });

  test('captura de 2 MiB (~2,7 MiB em base64) passa pelo WebSocket', () async {
    final (inbox, channel) = await connectTv();
    final adminInbox = Inbox(await connectAdmin(server, admin));
    final requestId = await ask(inbox);

    final big = fakeJpeg(maxScreenshotBytes);
    final message = result(requestId, big).encode();
    expect(message.length, greaterThan(2.6 * 1024 * 1024));
    channel.sink.add(message);

    await adminInbox
        .nextOfType(MessageTypes.deviceScreenshot)
        .timeout(const Duration(seconds: 10));
    expect((await fetch()).bodyBytes, hasLength(maxScreenshotBytes));
  });

  test('mensagem acima do limite fecha a conexão com 4400', () async {
    final (inbox, channel) = await connectTv();
    channel.sink.add('x' * (maxDeviceMessageChars + 1));

    expect(await inbox.closeCode(), WsCloseCodes.protocolError);
    // O servidor segue de pé.
    expect((await server.get('/health')).statusCode, 200);
  });

  test('remover a TV apaga a captura', () async {
    final (inbox, channel) = await connectTv();
    final adminInbox = Inbox(await connectAdmin(server, admin));
    final requestId = await ask(inbox);
    channel.sink.add(result(requestId, fakeJpeg()).encode());
    await adminInbox.nextOfType(MessageTypes.deviceScreenshot);

    final store = ScreenshotStore(clock: clock.call);
    expect(store.latest(tv.id), isNull);
    expect(
      (await server.send(
        'DELETE',
        '/api/v1/devices/${tv.id}',
        headers: admin,
      )).statusCode,
      204,
    );
    expect((await fetch()).statusCode, 404);
  });

  group('ScreenshotStore', () {
    test('forget apaga pedido, intervalo e captura', () {
      final store = ScreenshotStore(clock: clock.call);
      final id = store.begin('tv1');
      expect(
        store.accept(
          'tv1',
          ScreenshotResult.fromBytes(
            requestId: id,
            mime: 'image/jpeg',
            bytes: fakeJpeg(),
          ),
        ),
        isNull,
      );
      expect(store.latest('tv1'), isNotNull);

      store.forget('tv1');

      expect(store.latest('tv1'), isNull);
      expect(store.begin('tv1'), isNotEmpty); // sem intervalo
    });
  });
}
