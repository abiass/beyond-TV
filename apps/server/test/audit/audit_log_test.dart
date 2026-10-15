import 'package:beyond_server/server.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../support/test_server.dart';

void main() {
  late Database db;
  late FakeClock clock;

  setUp(() {
    db = openDatabase();
    clock = FakeClock();
    addTearDown(db.close);
  });

  void add(AuditLog log, [String path = '/api/v1/x']) =>
      log.record(method: 'POST', path: path, status: 200);

  test('grava e lista da mais nova para a mais antiga', () {
    final log = AuditLog(db, clock: clock.call);
    log.record(
      method: 'DELETE',
      path: '/api/v1/devices/a',
      status: 204,
      ip: '127.0.0.1',
    );
    clock.advance(const Duration(seconds: 1));
    add(log, '/api/v1/groups');

    final entries = log.list();

    expect(entries.map((e) => e.path), ['/api/v1/groups', '/api/v1/devices/a']);
    expect(entries.last.method, 'DELETE');
    expect(entries.last.status, 204);
    expect(entries.last.ip, '127.0.0.1');
    expect(entries.last.adminId, isNull);
    expect(entries.first.at, clock.now);
  });

  test('before pagina pelo id e limit corta', () {
    final log = AuditLog(db, clock: clock.call);
    for (var i = 0; i < 5; i++) {
      add(log, '/api/v1/n$i');
    }

    final first = log.list(limit: 2);
    final next = log.list(limit: 2, before: first.last.id);

    expect(first.map((e) => e.path), ['/api/v1/n4', '/api/v1/n3']);
    expect(next.map((e) => e.path), ['/api/v1/n2', '/api/v1/n1']);
  });

  test('retenção por idade', () {
    final log = AuditLog(db, clock: clock.call);
    add(log, '/api/v1/velha');
    clock.advance(const Duration(days: 89));
    add(log, '/api/v1/meia');
    expect(log.list(), hasLength(2));

    clock.advance(const Duration(days: 2));
    add(log, '/api/v1/nova');

    expect(log.list().map((e) => e.path), ['/api/v1/nova', '/api/v1/meia']);
  });

  test('retenção por quantidade', () {
    final log = AuditLog(db, clock: clock.call, maxRows: 3);
    for (var i = 0; i < 6; i++) {
      add(log, '/api/v1/n$i');
    }

    expect(log.list().map((e) => e.path), [
      '/api/v1/n5',
      '/api/v1/n4',
      '/api/v1/n3',
    ]);
  });

  test('apagar o admin mantém a linha com admin nulo', () {
    db.execute(
      "INSERT INTO admins (username, password_hash) VALUES ('a', 'h')",
    );
    final adminId = db.select('SELECT id FROM admins').single['id'] as int;
    final log = AuditLog(db, clock: clock.call);
    log.record(
      method: 'POST',
      path: '/api/v1/x',
      status: 200,
      adminId: adminId,
    );
    expect(log.list().single.adminName, 'a');

    db.execute('DELETE FROM admins');

    expect(log.list().single.adminId, isNull);
    expect(log.list().single.adminName, isNull);
  });
}
