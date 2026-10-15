import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beyond_protocol/beyond_protocol.dart';

import 'server_address.dart';

/// Procura servidores Beyond TV na rede local.
abstract interface class ServerDiscovery {
  /// Servidores que responderam, ordenados por nome.
  Future<List<ServerAddress>> discover();
}

/// Descoberta por UDP broadcast (veja a ADR 0004).
///
/// Envia [discoveryRequest] para o broadcast geral e para o broadcast de
/// cada rede da TV, duas vezes (UDP pode perder pacotes), e junta as
/// respostas que chegarem dentro de [timeout].
class UdpServerDiscovery implements ServerDiscovery {
  const UdpServerDiscovery({
    this.port = discoveryPort,
    this.timeout = const Duration(seconds: 3),
  });

  final int port;
  final Duration timeout;

  @override
  Future<List<ServerAddress>> discover() async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)
      ..broadcastEnabled = true;
    final found = <String, ServerAddress>{};

    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      try {
        final response = DiscoveryResponse.decode(datagram.data);
        // Servidor de outra versão do protocolo: o pareamento não daria certo.
        if (response.v != protocolVersion) return;
        found[response.serverId] = ServerAddress(
          host: datagram.address.address,
          port: response.port,
          name: response.name,
          serverId: response.serverId,
        );
      } on ProtocolException {
        // Algo na rede respondeu na mesma porta, mas não é um servidor nosso.
      }
    });

    try {
      final message = utf8.encode(discoveryRequest);
      final targets = await _broadcastTargets();
      for (var round = 0; round < 2; round++) {
        for (final target in targets) {
          socket.send(message, target, port);
        }
        await Future<void>.delayed(timeout ~/ 2);
      }
    } finally {
      await subscription.cancel();
      socket.close();
    }

    return found.values.toList()
      ..sort((a, b) => (a.name ?? a.host).compareTo(b.name ?? b.host));
  }

  /// Broadcast geral e o `x.y.z.255` de cada rede IPv4 da TV.
  ///
  /// Alguns roteadores não repassam o `255.255.255.255`, mas repassam o
  /// broadcast da sub-rede. Considera máscara /24, a mais comum em casa e em
  /// pequenos escritórios.
  static Future<List<InternetAddress>> _broadcastTargets() async {
    final targets = <String>{'255.255.255.255'};
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final address in interfaces.expand((i) => i.addresses)) {
        if (address.isLoopback) continue;
        final parts = address.address.split('.');
        targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
      }
    } on SocketException {
      // Sem acesso às interfaces: fica só com o broadcast geral.
    }
    return [for (final target in targets) InternetAddress(target)];
  }
}
