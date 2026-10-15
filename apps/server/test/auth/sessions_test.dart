import 'package:beyond_server/server.dart';
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../support/test_server.dart';

void main() {
  late Database db;
  late FakeClock clock;
  late SessionStore sessions;

  setUp(() {
    db = openDatabase();
    clock = FakeClock();
    sessions = SessionStore(db, clock: clock.call);
    db.execute(
      "INSERT INTO admins (id, username, password_hash) VALUES (1, 'admin', 'x')",
    );
  });

  tearDown(() => db.close());

  test('cria tokens distintos que encontram o administrador', () {
    final a = sessions.create(1);
    final b = sessions.create(1);

    expect(a, isNot(b));
    expect(a, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(sessions.findAdmin(a)?.username, 'admin');
    expect(sessions.findAdmin(b)?.username, 'admin');
  });

  test('grava a expiração em UTC daqui a 7 dias', () {
    sessions.create(1);

    final expiresAt = DateTime.parse(
      db.select('SELECT expires_at FROM sessions').single['expires_at']
          as String,
    );
    expect(expiresAt, clock.now.add(defaultSessionTtl));
  });

  test('purgeExpired só remove as vencidas', () {
    final old = sessions.create(1);
    clock.advance(const Duration(days: 3));
    final recent = sessions.create(1);
    clock.advance(const Duration(days: 5));

    expect(sessions.purgeExpired(), 1);
    expect(sessions.findAdmin(old), isNull);
    expect(sessions.findAdmin(recent), isNotNull);
  });

  group('tokenOf', () {
    String? tokenOf(String? cookie) => SessionStore.tokenOf(
      Request(
        'GET',
        Uri.parse('http://localhost/'),
        headers: {'cookie': ?cookie},
      ),
    );

    test('lê o cookie da sessão', () {
      expect(tokenOf('a=1; $sessionCookieName=abc; b=2'), 'abc');
    });

    test('ignora cookie ausente, vazio ou com outro nome', () {
      expect(tokenOf(null), isNull);
      expect(tokenOf('$sessionCookieName='), isNull);
      expect(tokenOf('outro_$sessionCookieName=abc'), isNull);
    });
  });
}
