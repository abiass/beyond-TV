import 'dart:convert';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_server/server.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/test_server.dart';

void main() {
  late FakeClock clock;
  late TestServer server;
  late Map<String, String> admin;

  const deviceInfo = DeviceInfo(
    appVersion: '0.4.0',
    manufacturer: 'Acme',
    model: 'TV 4K',
    androidVersion: '11',
  );

  setUp(() async {
    clock = FakeClock();
    server = await TestServer.start(clock: clock.call);
    final setup = await server.post(
      '/api/v1/setup',
      json: {'username': 'admin', 'password': 'senha-forte-1'},
    );
    admin = sessionHeader(sessionTokenFrom(setup)!);
  });

  Future<String> createCode() async {
    final response = await server.post('/api/v1/pairing-codes', headers: admin);
    return (jsonBody(response)! as Map)['code'] as String;
  }

  Future<http.Response> pair(String code) => server.post(
    '/api/v1/pair',
    json: PairRequest(code: code, deviceInfo: deviceInfo).toJson(),
  );

  test('troca o código por um token e cadastra a TV', () async {
    final code = await createCode();

    final response = await pair(code);

    expect(response.statusCode, 201);
    final result = PairResponse.fromJson(
      jsonBody(response)! as Map<String, Object?>,
    );
    final serverId = server.db
        .select("SELECT value FROM settings WHERE key = 'server_id'")
        .single['value'];
    expect(result.serverId, serverId);
    expect(result.deviceToken, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));

    final device = server.db.select('SELECT * FROM devices').single;
    expect(device['id'], result.deviceId);
    expect(device['name'], 'Acme TV 4K');
    expect(device['token_hash'], hashToken(result.deviceToken));
    expect(jsonDecode(device['info'] as String), deviceInfo.toJson());
  });

  test('o dashboard vê o código como pareado, com o nome da TV', () async {
    final code = await createCode();
    final paired = PairResponse.fromJson(
      jsonBody(await pair(code))! as Map<String, Object?>,
    );

    final response = await server.get(
      '/api/v1/pairing-codes/$code',
      headers: admin,
    );

    expect(jsonBody(response), {
      'code': code,
      'expiresAt': isA<String>(),
      'status': 'paired',
      'deviceId': paired.deviceId,
      'deviceName': 'Acme TV 4K',
    });
  });

  test('aceita o código em minúsculas', () async {
    final code = await createCode();

    expect((await pair(code.toLowerCase())).statusCode, 201);
  });

  test('não exige sessão nem cookie', () async {
    final code = await createCode();

    final response = await pair(code);

    expect(response.statusCode, 201);
    expect(response.headers['set-cookie'], isNull);
  });

  test('código malformado é inválido', () async {
    final response = await pair('0000');

    expect(response.statusCode, 400);
    expect(errorCode(response), 'invalid_code');
  });

  test('pedido sem deviceInfo responde 400', () async {
    final response = await server.post(
      '/api/v1/pair',
      json: {'code': await createCode()},
    );

    expect(response.statusCode, 400);
    expect(errorCode(response), 'bad_request');
    expect(server.db.select('SELECT * FROM devices'), isEmpty);
  });
}
