import 'dart:async';
import 'dart:convert';

import 'package:beyond_server/server.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

Request _get(String path) => Request('GET', Uri.parse('http://localhost$path'));

void main() {
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> subscription;

  setUp(() {
    records = [];
    Logger.root.level = Level.ALL;
    subscription = Logger.root.onRecord.listen(records.add);
  });

  tearDown(() => subscription.cancel());

  group('errorHandler', () {
    Handler wrap(Handler handler) =>
        const Pipeline().addMiddleware(errorHandler()).addHandler(handler);

    test('responde 500 genérico e registra o erro com stack trace', () async {
      final handler = wrap((_) => throw StateError('segredo interno'));

      final response = await handler(_get('/x'));
      final body = await response.readAsString();

      expect(response.statusCode, 500);
      expect(response.headers['content-type'], startsWith('application/json'));
      expect(jsonDecode(body), {
        'error': {
          'code': 'internal_error',
          'message': 'Erro interno do servidor.',
        },
      });
      expect(body, isNot(contains('segredo')));

      final record = records.single;
      expect(record.level, Level.SEVERE);
      expect(record.error, isA<StateError>());
      expect(record.stackTrace, isNotNull);
    });

    test('transforma ApiException na resposta que ela descreve', () async {
      final handler = wrap(
        (_) => throw const ApiException.badRequest('Campo obrigatório.'),
      );

      final response = await handler(_get('/x'));

      expect(response.statusCode, 400);
      expect(jsonDecode(await response.readAsString()), {
        'error': {'code': 'bad_request', 'message': 'Campo obrigatório.'},
      });
      expect(records, isEmpty);
    });

    test('repassa HijackException para o WebSocket funcionar', () {
      final handler = wrap((_) => throw const HijackException());

      expect(() => handler(_get('/x')), throwsA(isA<HijackException>()));
    });
  });

  group('requestLogger', () {
    Handler wrap(int status) => const Pipeline()
        .addMiddleware(requestLogger())
        .addHandler((_) => Response(status));

    test('registra método, caminho, status e duração sem a query', () async {
      await wrap(200)(_get('/api/x?token=segredo'));

      final event = records.single.object! as LogEvent;
      expect(records.single.level, Level.FINE);
      expect(event.fields, {
        'method': 'GET',
        'path': '/api/x',
        'status': 200,
        'ms': isA<int>(),
      });
      expect(event.fields.values, isNot(contains(contains('segredo'))));
    });

    test('usa info para 4xx e warning para 5xx', () async {
      await wrap(404)(_get('/a'));
      await wrap(503)(_get('/b'));

      expect(records.map((r) => r.level), [Level.INFO, Level.WARNING]);
    });
  });

  group('originCheck', () {
    final handler = const Pipeline()
        .addMiddleware(errorHandler())
        .addMiddleware(originCheck())
        .addHandler((_) => Response.ok('ok'));

    Future<Response> send(
      String method, {
      String? origin,
      String host = '192.168.0.10:8787',
    }) async => await handler(
      Request(
        method,
        Uri.parse('http://$host/api/v1/x'),
        headers: {'host': host, 'origin': ?origin},
      ),
    );

    test('aceita POST da mesma origem', () async {
      final response = await send('POST', origin: 'http://192.168.0.10:8787');

      expect(response.statusCode, 200);
    });

    test('aceita POST sem Origin (app da TV)', () async {
      expect((await send('POST')).statusCode, 200);
    });

    test('aceita a porta padrão escrita ou omitida', () async {
      final response = await send(
        'POST',
        host: 'example.local',
        origin: 'http://example.local:80',
      );

      expect(response.statusCode, 200);
    });

    for (final origin in [
      'http://evil.example',
      'http://192.168.0.10:9999',
      'https://192.168.0.10:8787',
      'null',
    ]) {
      test('recusa POST de $origin', () async {
        final response = await send('POST', origin: origin);

        expect(response.statusCode, 403);
        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['error']['code'], 'forbidden_origin');
      });
    }

    test('não bloqueia GET de outra origem', () async {
      final response = await send('GET', origin: 'http://evil.example');

      expect(response.statusCode, 200);
    });

    test('recusa DELETE de outra origem', () async {
      final response = await send('DELETE', origin: 'http://evil.example');

      expect(response.statusCode, 403);
    });
  });
}
