/// Porta HTTP padrão do servidor Beyond TV.
const defaultServerPort = 8787;

/// Endereço de um servidor Beyond TV na rede local.
final class ServerAddress {
  const ServerAddress({
    required this.host,
    this.port = defaultServerPort,
    this.name,
    this.serverId,
  });

  /// Lê o que foi digitado na TV: `192.168.0.10` ou `192.168.0.10:8787`.
  ///
  /// Também aceita nomes (`pc-sala.local`). Retorna `null` se não for um
  /// endereço válido.
  static ServerAddress? parse(String input) {
    final text = input.trim();
    final match = _pattern.firstMatch(text);
    if (match == null) return null;

    final host = match.group(1)!;
    final port =
        match.group(2) == null ? defaultServerPort : int.parse(match.group(2)!);
    if (port < 1 || port > 65535) return null;
    if (_looksLikeIpv4(host) && !_isValidIpv4(host)) return null;
    return ServerAddress(host: host, port: port);
  }

  final String host;
  final int port;

  /// Nome anunciado pelo servidor na descoberta (o nome do PC).
  final String? name;

  /// Identificador do servidor, quando já conhecido.
  final String? serverId;

  /// `host:port`, como a pessoa digitaria.
  String get hostPort => '$host:$port';

  /// URL de [path] neste servidor.
  Uri resolve(String path) =>
      Uri(scheme: 'http', host: host, port: port, path: path);

  @override
  bool operator ==(Object other) =>
      other is ServerAddress &&
      other.host == host &&
      other.port == port &&
      other.name == name &&
      other.serverId == serverId;

  @override
  int get hashCode => Object.hash(host, port, name, serverId);

  @override
  String toString() => 'ServerAddress(${name ?? '-'} @ $hostPort)';

  static final _pattern = RegExp(r'^([A-Za-z0-9.-]+)(?::(\d{1,5}))?$');

  static bool _looksLikeIpv4(String host) => RegExp(r'^[\d.]+$').hasMatch(host);

  static bool _isValidIpv4(String host) {
    final parts = host.split('.');
    return parts.length == 4 &&
        parts.every((part) {
          final value = int.tryParse(part);
          return value != null && value >= 0 && value <= 255;
        });
  }
}
