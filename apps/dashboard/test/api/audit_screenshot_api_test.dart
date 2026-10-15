import 'dart:convert';

import 'package:beyond_dashboard/src/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final base = Uri.parse('http://192.168.0.10:8787/');
  late http.Request sent;

  ApiClient clientWith(
    int status,
    Object? body, {
    Map<String, String> headers = const {},
  }) =>
      ApiClient(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            body == null ? '' : jsonEncode(body),
            status,
            headers: headers,
          );
        }),
        baseUri: base,
      );

  test('requestScreenshot manda o comando e devolve o requestId', () async {
    final id =
        await clientWith(202, {'requestId': 'r1'}).requestScreenshot('tv1');

    expect(id, 'r1');
    expect(sent.method, 'POST');
    expect(sent.url.path, '/api/v1/devices/tv1/commands');
    expect(jsonDecode(sent.body), {'type': 'screenshot'});
  });

  test('requestScreenshot traduz 409 e 429', () async {
    Map<String, Object?> error(String code) => {
          'error': {'code': code, 'message': 'em inglês'},
        };
    await expectLater(
      clientWith(409, error('device_offline')).requestScreenshot('a'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.message, 'message', 'A TV está offline.'),
      ),
    );
    await expectLater(
      clientWith(429, error('too_many_requests')).requestScreenshot('a'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Aguarde alguns segundos para capturar de novo.',
        ),
      ),
    );
  });

  test('screenshotUrl leva o cache-bust', () {
    final url = ApiClient(baseUri: base)
        .screenshotUrl('a', capturedAt: DateTime.utc(2026, 10, 1));
    expect(
      url.toString(),
      'http://192.168.0.10:8787/api/v1/devices/a/screenshot'
      '?t=${DateTime.utc(2026, 10, 1).millisecondsSinceEpoch}',
    );
  });

  test('getScreenshotInfo lê X-Captured-At e devolve null no 404', () async {
    final at = await clientWith(
      200,
      null,
      headers: {'x-captured-at': '2026-10-01T12:00:00.000Z'},
    ).getScreenshotInfo('a');
    expect(at, DateTime.utc(2026, 10, 1, 12));

    expect(
      await clientWith(404, {
        'error': {'code': 'no_screenshot', 'message': 'x'},
      }).getScreenshotInfo('a'),
      isNull,
    );
  });

  test('listAudit lê as entradas e manda limit e before', () async {
    final entries = await clientWith(200, {
      'entries': [
        {
          'id': 7,
          'at': '2026-10-01T12:00:00.000Z',
          'method': 'DELETE',
          'path': '/api/v1/devices/a',
          'status': 204,
          'adminId': 1,
          'adminName': 'admin',
          'ip': '192.168.0.10',
        },
        {
          'id': 6,
          'at': '2026-10-01T11:00:00.000Z',
          'method': 'POST',
          'path': '/api/v1/auth/login',
          'status': 401,
          'adminId': null,
          'adminName': null,
          'ip': null,
        },
      ],
    }).listAudit(limit: 50, before: 8);

    expect(sent.method, 'GET');
    expect(sent.url.path, '/api/v1/audit');
    expect(sent.url.queryParameters, {'limit': '50', 'before': '8'});
    expect(entries.map((e) => e.id), [7, 6]);
    expect(entries.first.adminName, 'admin');
    expect(entries.last.adminName, isNull);
    expect(entries.last.status, 401);
  });
}
