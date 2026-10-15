import 'dart:convert';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../server/server_address.dart';

/// Credenciais da TV depois do pareamento.
final class Credentials {
  const Credentials({
    required this.deviceId,
    required this.deviceToken,
    required this.server,
  });

  /// Junta a resposta do pareamento com o servidor que a emitiu.
  factory Credentials.fromPairing(ServerAddress server, PairResponse pair) =>
      Credentials(
        deviceId: pair.deviceId,
        deviceToken: pair.deviceToken,
        server: ServerAddress(
          host: server.host,
          port: server.port,
          name: server.name,
          serverId: pair.serverId,
        ),
      );

  /// Lê as credenciais salvas. Lança [FormatException] se estiverem
  /// incompletas.
  factory Credentials.fromJson(Map<String, Object?> json) => switch (json) {
        {
          'deviceId': final String deviceId,
          'deviceToken': final String deviceToken,
          'server': {
                'host': final String host,
                'port': final int port,
                'serverId': final String serverId,
              } &&
              final server,
        } =>
          Credentials(
            deviceId: deviceId,
            deviceToken: deviceToken,
            server: ServerAddress(
              host: host,
              port: port,
              name: server['name'] as String?,
              serverId: serverId,
            ),
          ),
        _ => throw const FormatException('credenciais incompletas'),
      };

  final String deviceId;

  /// Token secreto da TV. Só existe aqui e, em hash, no servidor.
  final String deviceToken;

  /// Servidor que pareou a TV, com o `serverId`. A TV só usa o token com
  /// esse mesmo servidor.
  final ServerAddress server;

  Map<String, Object?> toJson() => {
        'deviceId': deviceId,
        'deviceToken': deviceToken,
        'server': {
          'host': server.host,
          'port': server.port,
          if (server.name != null) 'name': server.name,
          'serverId': server.serverId,
        },
      };

  @override
  String toString() => 'Credentials($deviceId @ ${server.hostPort})';
}

/// Onde as credenciais ficam guardadas na TV.
abstract interface class CredentialStore {
  /// Credenciais salvas, ou `null` se a TV ainda não foi pareada.
  Future<Credentials?> load();

  Future<void> save(Credentials credentials);

  Future<void> clear();
}

/// Guarda as credenciais no `flutter_secure_storage`, cifradas com uma
/// chave do Android Keystore.
class SecureCredentialStore implements CredentialStore {
  const SecureCredentialStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  static const _key = 'beyond.credentials';

  @override
  Future<Credentials?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      return Credentials.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object {
      // Dado corrompido ou de uma versão antiga: pareia de novo.
      await clear();
      return null;
    }
  }

  @override
  Future<void> save(Credentials credentials) =>
      _storage.write(key: _key, value: jsonEncode(credentials.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
