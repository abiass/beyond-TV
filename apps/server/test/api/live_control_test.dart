import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/realtime_support.dart';
import '../support/test_server.dart';

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

  tearDown(() => server.close());

  Future<Inbox> connectTv() async {
    final channel = await connectDevice(server, tv.token);
    final inbox = Inbox(channel);
    sendHello(channel);
    await inbox.nextOfType(MessageTypes.contentSync);
    return inbox;
  }

  Future<http.Response> post(String path, {Object? json}) =>
      server.post('/api/v1/devices/${tv.id}$path', json: json, headers: admin);

  List<String> auditedPaths() => [
    for (final row in server.db.select('SELECT path FROM audit_log'))
      row['path'] as String,
  ];

  test('quadro ao vivo: captura menor e intervalo curto', () async {
    final inbox = await connectTv();

    expect((await post('/live/frame')).statusCode, 202);
    final cmd = await inbox.nextOfType(MessageTypes.cmdScreenshot);
    expect(ScreenshotRequest.fromJson(cmd.payload).maxWidth, liveFrameMaxWidth);

    // Logo em seguida, ainda no intervalo: 429.
    expect((await post('/live/frame')).statusCode, 429);

    clock.advance(liveFrameCooldown);
    expect((await post('/live/frame')).statusCode, 202);
  });

  test('a captura normal continua com o intervalo de 5 s', () async {
    await connectTv();

    expect(
      (await post('/commands', json: {'type': 'screenshot'})).statusCode,
      202,
    );
    clock.advance(liveFrameCooldown);
    expect(
      (await post('/commands', json: {'type': 'screenshot'})).statusCode,
      429,
    );
  });

  test('entrada chega na TV como cmd.input', () async {
    final inbox = await connectTv();

    final response = await post(
      '/live/input',
      json: const RemoteInput.tap(0.5, 0.25).toJson(),
    );

    expect(response.statusCode, 202);
    final cmd = await inbox.nextOfType(MessageTypes.cmdInput);
    final input = RemoteInput.fromJson(cmd.payload);
    expect(input.kind, RemoteInputKind.tap);
    expect((input.x, input.y), (0.5, 0.25));
  });

  test('texto chega inteiro na TV', () async {
    final inbox = await connectTv();

    await post('/live/input', json: const RemoteInput.text('s3nh@').toJson());

    final cmd = await inbox.nextOfType(MessageTypes.cmdInput);
    expect(RemoteInput.fromJson(cmd.payload).text, 's3nh@');
  });

  test('entrada inválida dá 400', () async {
    await connectTv();

    final response = await post(
      '/live/input',
      json: {'kind': 'key', 'key': 'x'},
    );

    expect(response.statusCode, 400);
  });

  test('TV offline dá 409 em tudo', () async {
    expect((await post('/live')).statusCode, 409);
    expect((await post('/live/frame')).statusCode, 409);
    expect(
      (await post(
        '/live/input',
        json: const RemoteInput.key('enter').toJson(),
      )).statusCode,
      409,
    );
  });

  test('exige o administrador', () async {
    await connectTv();

    for (final path in ['/live', '/live/frame', '/live/input']) {
      final response = await server.post(
        '/api/v1/devices/${tv.id}$path',
        json: const RemoteInput.key('enter').toJson(),
      );
      expect(response.statusCode, 401, reason: path);
    }
  });

  test(
    'a auditoria registra a abertura, mas não quadros nem entradas',
    () async {
      await connectTv();

      expect((await post('/live')).statusCode, 204);
      await post('/live/frame');
      await post('/live/input', json: const RemoteInput.text('senha').toJson());

      final paths = auditedPaths();
      expect(paths, contains('/api/v1/devices/${tv.id}/live'));
      expect(paths.where((p) => p.contains('/live/')), isEmpty);
    },
  );
}
