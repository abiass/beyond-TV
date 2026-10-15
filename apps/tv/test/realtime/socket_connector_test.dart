import 'dart:async';
import 'dart:io';

import 'package:beyond_tv/src/realtime/socket_connector.dart';
import 'package:flutter_test/flutter_test.dart';

const _limite = Timeout(Duration(seconds: 10));

void main() {
  test(
    'conecta com o header, e o servidor ecoa as mensagens',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final auth = Completer<String?>();
      server.listen((request) async {
        auth.complete(request.headers.value('authorization'));
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen(socket.add);
      });

      final channel = await ioConnector(
        Uri.parse('ws://127.0.0.1:${server.port}/ws/device'),
        {'authorization': 'Bearer abc'},
      );
      addTearDown(() => channel.sink.close());

      expect(await auth.future, 'Bearer abc');
      channel.sink.add('oi');
      expect(await channel.stream.first, 'oi');
    },
    timeout: _limite,
  );

  test(
    'falha se o servidor recusa o upgrade com 403',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) {
        request.response.statusCode = 403;
        request.response.close();
      });

      await expectLater(
        ioConnector(
          Uri.parse('ws://127.0.0.1:${server.port}/ws/device'),
          {},
        ),
        throwsA(anything),
      );
    },
    timeout: _limite,
  );

  test(
    'falha se ninguém escuta na porta',
    () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();

      await expectLater(
        ioConnector(
          Uri.parse('ws://127.0.0.1:$port/ws/device'),
          {},
        ),
        throwsA(anything),
      );
    },
    timeout: _limite,
  );
}
