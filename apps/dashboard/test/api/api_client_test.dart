import 'dart:convert';

import 'package:beyond_dashboard/src/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final base = Uri.parse('http://192.168.0.10:8787/');

  ApiClient clientWith(
    Future<http.Response> Function(http.Request request) handler,
  ) =>
      ApiClient(client: MockClient(handler), baseUri: base);

  test('envia login em JSON para a mesma origem', () async {
    late http.Request sent;
    final api = clientWith((request) async {
      sent = request;
      return http.Response(jsonEncode({'username': 'admin'}), 200);
    });

    expect(await api.login(username: 'admin', password: 'x'), 'admin');
    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'http://192.168.0.10:8787/api/v1/auth/login');
    expect(sent.headers['content-type'], startsWith('application/json'));
    expect(jsonDecode(sent.body), {'username': 'admin', 'password': 'x'});
  });

  test('transforma o erro da API em ApiException', () async {
    final api = clientWith(
      (_) async => http.Response(
        jsonEncode({
          'error': {'code': 'invalid_login', 'message': 'Senha errada.'},
        }),
        401,
      ),
    );

    expect(
      () => api.login(username: 'admin', password: 'x'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'invalid_login')
            .having((e) => e.status, 'status', 401)
            .having((e) => e.message, 'message', 'Senha errada.'),
      ),
    );
  });

  test('currentUser devolve null quando não há sessão', () async {
    final api = clientWith(
      (_) async => http.Response(
        jsonEncode({
          'error': {'code': 'unauthorized', 'message': 'Faça login.'},
        }),
        401,
      ),
    );

    expect(await api.currentUser(), isNull);
  });

  test('falha de rede vira mensagem amigável', () async {
    final api = clientWith((_) => throw http.ClientException('recusado'));

    expect(
      api.isConfigured,
      throwsA(
        isA<ApiException>().having((e) => e.status, 'status', isNull),
      ),
    );
  });
}
