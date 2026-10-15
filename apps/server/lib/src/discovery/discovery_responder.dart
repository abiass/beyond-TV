import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:logging/logging.dart';

import '../logging.dart';

final _log = Logger('discovery');

/// Responde à descoberta das TVs na rede local.
///
/// A TV manda [discoveryRequest] em broadcast UDP; o servidor responde em
/// unicast para o endereço de origem com um [DiscoveryResponse]. Qualquer
/// outro pacote é ignorado. Veja a ADR 0004.
class DiscoveryResponder {
  DiscoveryResponder._(this._socket, this._response) {
    _subscription = _socket.listen((event) {
      if (event == RawSocketEvent.read) _handle();
    });
  }

  /// Escuta em [port] (UDP) e responde com [response].
  static Future<DiscoveryResponder> bind({
    required int port,
    required DiscoveryResponse response,
    InternetAddress? address,
  }) async {
    final socket = await RawDatagramSocket.bind(
      address ?? InternetAddress.anyIPv4,
      port,
    );
    return DiscoveryResponder._(socket, response);
  }

  final RawDatagramSocket _socket;
  final DiscoveryResponse _response;
  late final StreamSubscription<RawSocketEvent> _subscription;

  /// Porta UDP em uso (útil quando o bind foi na porta 0).
  int get port => _socket.port;

  void _handle() {
    final datagram = _socket.receive();
    if (datagram == null) return;
    // Pacotes grandes não são descoberta; nem tenta decodificar.
    if (datagram.data.length > 64) return;

    final message = utf8.decode(datagram.data, allowMalformed: true).trim();
    if (message != discoveryRequest) return;

    _socket.send(_response.encode(), datagram.address, datagram.port);
    _log.fine(
      LogEvent('descoberta respondida', {
        'tv': '${datagram.address.address}:${datagram.port}',
      }),
    );
  }

  Future<void> close() async {
    await _subscription.cancel();
    _socket.close();
  }
}
