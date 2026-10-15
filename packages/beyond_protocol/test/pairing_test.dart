import 'dart:convert';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('código de pareamento', () {
    test('o alfabeto não tem caracteres ambíguos', () {
      for (final char in ['0', 'O', '1', 'I', 'L']) {
        expect(pairingCodeAlphabet, isNot(contains(char)));
      }
      expect(pairingCodeAlphabet.split('').toSet(), hasLength(31));
    });

    test('normaliza maiúsculas, espaços e hífens', () {
      expect(normalizePairingCode(' k7m-4qx '), 'K7M4QX');
    });

    test('reconhece o formato válido', () {
      expect(isWellFormedPairingCode('K7M4QX'), isTrue);
      expect(isWellFormedPairingCode('K7M4Q'), isFalse);
      expect(isWellFormedPairingCode('K7M4QXX'), isFalse);
      expect(isWellFormedPairingCode('K7M4Q0'), isFalse);
      expect(isWellFormedPairingCode('k7m4qx'), isFalse);
    });
  });

  group('DeviceInfo', () {
    const full = DeviceInfo(
      appVersion: '0.4.0',
      manufacturer: 'Acme',
      model: 'TV 4K',
      androidVersion: '11',
      screenWidth: 3840,
      screenHeight: 2160,
    );

    test('ida e volta pelo JSON', () {
      final json = jsonDecode(jsonEncode(full.toJson()));

      expect(DeviceInfo.fromJson(json as Map<String, Object?>), full);
    });

    test('omite campos ausentes e aceita só a versão do app', () {
      const minimal = DeviceInfo(appVersion: '0.4.0');

      expect(minimal.toJson(), {'appVersion': '0.4.0'});
      expect(DeviceInfo.fromJson({'appVersion': '0.4.0'}), minimal);
    });

    test('recusa tipos errados', () {
      expect(
        () => DeviceInfo.fromJson({'appVersion': 4}),
        throwsA(isA<ProtocolException>()),
      );
      expect(
        () => DeviceInfo.fromJson({'appVersion': '1', 'screenWidth': '1920'}),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('sugere um nome a partir de fabricante e modelo', () {
      expect(full.suggestedName, 'Acme TV 4K');
      expect(
        const DeviceInfo(appVersion: '1', manufacturer: 'Acme', model: 'ACME X')
            .suggestedName,
        'ACME X',
      );
      expect(
        const DeviceInfo(appVersion: '1', model: 'X1').suggestedName,
        'X1',
      );
      expect(const DeviceInfo(appVersion: '1').suggestedName, 'Nova TV');
    });
  });

  test('PairRequest ida e volta pelo JSON', () {
    const request = PairRequest(
      code: 'K7M4QX',
      deviceInfo: DeviceInfo(appVersion: '0.4.0', model: 'X1'),
    );

    final decoded = PairRequest.fromJson(
      jsonDecode(jsonEncode(request.toJson())) as Map<String, Object?>,
    );

    expect(decoded.code, 'K7M4QX');
    expect(decoded.deviceInfo, request.deviceInfo);
  });

  test('PairRequest sem deviceInfo é inválido', () {
    expect(
      () => PairRequest.fromJson({'code': 'K7M4QX'}),
      throwsA(isA<ProtocolException>()),
    );
  });

  test('PairResponse ida e volta pelo JSON', () {
    const response = PairResponse(
      deviceId: 'd1',
      deviceToken: 'segredo',
      serverId: 's1',
    );

    final decoded = PairResponse.fromJson(response.toJson());

    expect(decoded.deviceId, 'd1');
    expect(decoded.deviceToken, 'segredo');
    expect(decoded.serverId, 's1');
    expect(decoded.toString(), isNot(contains('segredo')));
  });

  test('PairingCode converte a expiração para UTC', () {
    final code = PairingCode.fromJson({
      'code': 'K7M4QX',
      'expiresAt': '2026-10-14T09:10:00-03:00',
    });

    expect(code.expiresAt, DateTime.utc(2026, 10, 14, 12, 10));
    expect(code.toJson()['expiresAt'], '2026-10-14T12:10:00.000Z');
  });

  group('descoberta', () {
    test('a mensagem de descoberta carrega a versão do protocolo', () {
      expect(discoveryRequest, 'BEYONDTV_DISCOVER v$protocolVersion');
    });

    test('resposta ida e volta pelos bytes', () {
      const response = DiscoveryResponse(
        name: 'PC-SALA',
        port: 8787,
        serverId: 'abc',
      );

      final decoded = DiscoveryResponse.decode(response.encode());

      expect(decoded.name, 'PC-SALA');
      expect(decoded.port, 8787);
      expect(decoded.serverId, 'abc');
      expect(decoded.v, protocolVersion);
    });

    test('recusa respostas malformadas', () {
      for (final raw in [
        'não é json',
        '[]',
        '{"v":1,"name":"x","serverId":"a"}',
        '{"v":1,"name":"x","serverId":"a","port":70000}',
      ]) {
        expect(
          () => DiscoveryResponse.decode(utf8.encode(raw)),
          throwsA(isA<ProtocolException>()),
          reason: raw,
        );
      }
    });
  });
}
