import 'package:bcrypt/bcrypt.dart';
import 'package:test/test.dart';

import '../support/test_server.dart';

void main() {
  late TestServer server;

  setUp(() async => server = await TestServer.start());

  Future<void> createAdmin() async {
    final response = await server.post(
      '/api/v1/setup',
      json: {'username': 'admin', 'password': 'senha-forte-1'},
    );
    expect(response.statusCode, 201);
  }

  test('status indica que falta configurar num banco novo', () async {
    final response = await server.get('/api/v1/setup/status');

    expect(response.statusCode, 200);
    expect(jsonBody(response), {'configured': false});
  });

  test('cria o administrador com a senha em bcrypt', () async {
    final response = await server.post(
      '/api/v1/setup',
      json: {'username': ' admin ', 'password': 'senha-forte-1'},
    );

    expect(response.statusCode, 201);
    expect(jsonBody(response), {'username': 'admin'});

    final row = server.db.select('SELECT * FROM admins').single;
    expect(row['username'], 'admin');
    final hash = row['password_hash'] as String;
    expect(hash, isNot(contains('senha-forte-1')));
    expect(BCrypt.checkpw('senha-forte-1', hash), isTrue);

    final status = await server.get('/api/v1/setup/status');
    expect(jsonBody(status), {'configured': true});
  });

  test('recusa um segundo setup', () async {
    await createAdmin();

    final response = await server.post(
      '/api/v1/setup',
      json: {'username': 'intruso', 'password': 'outra-senha-1'},
    );

    expect(response.statusCode, 409);
    expect(errorCode(response), 'already_configured');
    expect(server.db.select('SELECT * FROM admins'), hasLength(1));
  });

  test('setups simultâneos criam um único administrador', () async {
    final responses = await Future.wait([
      for (var i = 0; i < 3; i++)
        server.post(
          '/api/v1/setup',
          json: {'username': 'admin$i', 'password': 'senha-forte-1'},
        ),
    ]);

    expect(responses.where((r) => r.statusCode == 201), hasLength(1));
    expect(server.db.select('SELECT * FROM admins'), hasLength(1));
  });

  group('valida', () {
    for (final (description, body) in [
      ('senha curta', {'username': 'admin', 'password': 'curta'}),
      ('senha acima de 72 bytes', {'username': 'admin', 'password': 'ç' * 37}),
      ('usuário curto', {'username': 'ab', 'password': 'senha-forte-1'}),
      (
        'usuário com espaço',
        {'username': 'a b c', 'password': 'senha-forte-1'},
      ),
    ]) {
      test(description, () async {
        final response = await server.post('/api/v1/setup', json: body);

        expect(response.statusCode, 400);
        expect(errorCode(response), 'invalid_credentials');
        expect(server.db.select('SELECT * FROM admins'), isEmpty);
      });
    }

    test('campos ausentes', () async {
      final response = await server.post(
        '/api/v1/setup',
        json: {'username': 'admin'},
      );

      expect(response.statusCode, 400);
      expect(errorCode(response), 'bad_request');
    });

    test('corpo que não é JSON', () async {
      final response = await server.post(
        '/api/v1/setup',
        headers: {'content-type': 'text/plain'},
      );

      expect(response.statusCode, 400);
    });
  });
}
