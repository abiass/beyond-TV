import 'package:beyond_tv/src/server/server_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lê IP com e sem porta', () {
    expect(
      ServerAddress.parse(' 192.168.0.10 '),
      const ServerAddress(host: '192.168.0.10'),
    );
    expect(
      ServerAddress.parse('192.168.0.10:9000'),
      const ServerAddress(host: '192.168.0.10', port: 9000),
    );
  });

  test('aceita nome de host', () {
    expect(ServerAddress.parse('pc-sala.local')?.host, 'pc-sala.local');
  });

  test('recusa endereços inválidos', () {
    for (final input in [
      '',
      '192.168.0',
      '192.168.0.256',
      '192.168.0.10:0',
      '192.168.0.10:70000',
      'http://192.168.0.10',
      '192.168.0.10/painel',
    ]) {
      expect(ServerAddress.parse(input), isNull, reason: input);
    }
  });

  test('monta URLs http no servidor', () {
    expect(
      const ServerAddress(host: '192.168.0.10').resolve('/health').toString(),
      'http://192.168.0.10:8787/health',
    );
  });
}
