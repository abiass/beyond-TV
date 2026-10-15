import 'package:beyond_server/server.dart';
import 'package:test/test.dart';

void main() {
  const hasher = PasswordHasher(cost: 4);

  test('confere a senha certa e recusa a errada', () async {
    final hash = await hasher.hash('senha-forte-1');

    expect(hash, startsWith(r'$2a$04$'));
    expect(await hasher.verify('senha-forte-1', hash), isTrue);
    expect(await hasher.verify('senha-forte-2', hash), isFalse);
  });

  test('recusa senha acima de 72 bytes sem lançar erro', () async {
    final hash = await hasher.hash('senha-forte-1');

    expect(await hasher.verify('x' * 100, hash), isFalse);
  });

  test('gera hashes diferentes para a mesma senha (salt)', () async {
    expect(
      await hasher.hash('senha-forte-1'),
      isNot(await hasher.hash('senha-forte-1')),
    );
  });
}
