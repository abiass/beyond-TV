import 'package:beyond_tv/src/server/tv_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fakes.dart';

void main() {
  test('unpairSelf manda DELETE /api/v1/device com o Bearer', () async {
    late http.Request seen;
    final api = TvApi(
      client: MockClient((request) async {
        seen = request;
        return http.Response('', 204);
      }),
    );

    await api.unpairSelf(pcSala, 'segredo');

    expect(seen.method, 'DELETE');
    expect(seen.url.toString(), 'http://192.168.0.10:8787/api/v1/device');
    expect(seen.headers['Authorization'], 'Bearer segredo');
  });

  test('unpairSelf lança com o servidor fora do ar', () async {
    final api = TvApi(
      client: MockClient((request) async {
        throw http.ClientException('recusada', request.url);
      }),
    );

    expect(
      api.unpairSelf(pcSala, 'segredo'),
      throwsA(isA<TvApiException>()),
    );
  });

  test('unpairSelf lança com 401', () async {
    final api = TvApi(
      client: MockClient(
        (_) async => apiError(401, 'unauthorized', 'Não autorizado.'),
      ),
    );

    expect(
      api.unpairSelf(pcSala, 'segredo'),
      throwsA(isA<TvApiException>()),
    );
  });
}
