import 'package:args/args.dart';
import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:logging/logging.dart';

/// Porta HTTP padrão (dashboard, API, mídia e WebSocket).
const defaultHttpPort = 8787;

/// Porta UDP padrão da descoberta (a mesma que as TVs procuram).
const defaultDiscoveryPort = discoveryPort;

/// Pasta padrão dos dados de execução, relativa ao diretório atual.
const defaultDataDir = 'data';

/// Pasta padrão do build do dashboard, relativa à raiz do repositório.
const defaultWebDir = 'apps/dashboard/build/web';

/// Níveis de log aceitos em `--log-level`, do mais ao menos detalhado.
const logLevels = {
  'debug': Level.FINE,
  'info': Level.INFO,
  'warning': Level.WARNING,
  'error': Level.SEVERE,
};

/// Erro de configuração inválida, com mensagem pronta para o usuário.
class ConfigException implements Exception {
  ConfigException(this.message);

  final String message;

  @override
  String toString() => 'ConfigException: $message';
}

/// Configuração do servidor.
///
/// Cada opção vem, em ordem de prioridade, do argumento de linha de comando,
/// da variável de ambiente ou do valor padrão.
class ServerConfig {
  const ServerConfig({
    this.port = defaultHttpPort,
    this.discoveryPort = defaultDiscoveryPort,
    this.dataDir = defaultDataDir,
    this.webDir = defaultWebDir,
    this.logLevel = Level.INFO,
  });

  /// Lê a configuração de [args] e [environment].
  ///
  /// Lança [ConfigException] se algum valor for inválido. Quando
  /// `--help` é passado, retorna `null`; o texto de ajuda está em [usage].
  static ServerConfig? parse(
    List<String> args, {
    Map<String, String> environment = const {},
  }) {
    final ArgResults results;
    try {
      results = _parser.parse(args);
    } on FormatException catch (e) {
      throw ConfigException(e.message);
    }
    if (results.flag('help')) return null;

    String? option(String name, String envVar) {
      final value = results.option(name) ?? environment[envVar];
      return (value == null || value.trim().isEmpty) ? null : value.trim();
    }

    return ServerConfig(
      port: _parsePort(option('port', 'BEYOND_PORT'), defaultHttpPort),
      discoveryPort: _parsePort(
        option('discovery-port', 'BEYOND_DISCOVERY_PORT'),
        defaultDiscoveryPort,
      ),
      dataDir: option('data-dir', 'BEYOND_DATA_DIR') ?? defaultDataDir,
      webDir: option('web-dir', 'BEYOND_WEB_DIR') ?? defaultWebDir,
      logLevel: _parseLogLevel(option('log-level', 'BEYOND_LOG_LEVEL')),
    );
  }

  /// Texto de ajuda com todas as opções.
  static String get usage => _parser.usage;

  /// Porta TCP do HTTP e do WebSocket.
  final int port;

  /// Porta UDP em que o servidor responde à descoberta das TVs.
  final int discoveryPort;

  /// Pasta onde ficam o banco, as mídias e os logs.
  final String dataDir;

  /// Pasta com o build do dashboard (`flutter build web`).
  final String webDir;

  /// Nível mínimo das mensagens de log.
  final Level logLevel;

  static int _parsePort(String? raw, int defaultPort) {
    if (raw == null) return defaultPort;
    final port = int.tryParse(raw);
    if (port == null || port < 1 || port > 65535) {
      throw ConfigException(
        'Porta inválida: "$raw". Use um número de 1 a 65535.',
      );
    }
    return port;
  }

  static Level _parseLogLevel(String? raw) {
    if (raw == null) return Level.INFO;
    final level = logLevels[raw.toLowerCase()];
    if (level == null) {
      throw ConfigException(
        'Nível de log inválido: "$raw". Use ${logLevels.keys.join(', ')}.',
      );
    }
    return level;
  }

  static final _parser = ArgParser()
    ..addOption(
      'port',
      abbr: 'p',
      help: 'Porta HTTP. Variável de ambiente: BEYOND_PORT.',
      valueHelp: '$defaultHttpPort',
    )
    ..addOption(
      'discovery-port',
      help:
          'Porta UDP da descoberta pelas TVs. '
          'Variável de ambiente: BEYOND_DISCOVERY_PORT.',
      valueHelp: '$defaultDiscoveryPort',
    )
    ..addOption(
      'data-dir',
      abbr: 'd',
      help:
          'Pasta de dados (banco, mídias e logs). '
          'Variável de ambiente: BEYOND_DATA_DIR.',
      valueHelp: defaultDataDir,
    )
    ..addOption(
      'web-dir',
      help:
          'Pasta do build do dashboard. '
          'Variável de ambiente: BEYOND_WEB_DIR.',
      valueHelp: defaultWebDir,
    )
    ..addOption(
      'log-level',
      help: 'Nível de log. Variável de ambiente: BEYOND_LOG_LEVEL.',
      allowed: logLevels.keys,
      valueHelp: 'info',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Mostra esta ajuda.');
}
