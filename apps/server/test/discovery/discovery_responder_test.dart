import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_server/server.dart';
import 'package:test/test.dart';

void main() {
  late DiscoveryResponder responder;
  late RawDatagramSocket tv;
  late StreamController<Datagram> received;

  setUp(() async {
    responder = await DiscoveryResponder.bind(
      port: 0,
      address: InternetAddress.loopbackIPv4,
      response: const DiscoveryResponse(
        name: 'PC-SALA',
        port: 8787,
        serverId: 'abc',
      ),
    );
    tv = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    received = StreamController();
    tv.listen((event) {
      if (event != RawSocketEvent.read) return;
      if (tv.receive() case final datagram?) received.add(datagram);
    });
  });

  tearDown(() async {
    tv.close();
    await received.close();
    await responder.close();
  });

  void send(String message) => tv.send(
    utf8.encode(message),
    InternetAddress.loopbackIPv4,
    responder.port,
  );

  test('responde à descoberta com nome, porta e serverId', () async {
    send(discoveryRequest);

    final datagram = await received.stream.first.timeout(
      const Duration(seconds: 5),
    );
    final response = DiscoveryResponse.decode(datagram.data);
    expect(response.name, 'PC-SALA');
    expect(response.port, 8787);
    expect(response.serverId, 'abc');
    expect(response.v, protocolVersion);
    expect(datagram.address, InternetAddress.loopbackIPv4);
  });

  test('ignora pacotes que não são a descoberta', () async {
    send('BEYONDTV_DISCOVER v999');
    send('olá');
    send('x' * 1000);

    await expectLater(
      received.stream.first.timeout(const Duration(milliseconds: 500)),
      throwsA(isA<TimeoutException>()),
    );
  });
}
