import 'device_info.dart';
import 'json_fields.dart';

/// Caracteres permitidos no código de pareamento.
///
/// Sem 0/O e 1/I/L, que se confundem na tela da TV.
const pairingCodeAlphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

/// Quantidade de caracteres do código de pareamento.
const pairingCodeLength = 6;

/// Validade do código de pareamento.
const pairingCodeTtl = Duration(minutes: 10);

/// Normaliza o que foi digitado: maiúsculas, sem espaços nem hífens.
String normalizePairingCode(String input) =>
    input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');

/// Indica se [code] (já normalizado) tem o formato de um código válido.
bool isWellFormedPairingCode(String code) =>
    code.length == pairingCodeLength &&
    code.split('').every(pairingCodeAlphabet.contains);

/// Código gerado no dashboard (`POST /api/v1/pairing-codes`).
final class PairingCode {
  PairingCode({required this.code, required DateTime expiresAt})
      : expiresAt = expiresAt.toUtc();

  factory PairingCode.fromJson(Map<String, Object?> json) => PairingCode(
        code: json.field<String>('code'),
        expiresAt: json.dateField('expiresAt'),
      );

  final String code;

  /// Momento em que o código deixa de valer, em UTC.
  final DateTime expiresAt;

  Map<String, Object?> toJson() => {
        'code': code,
        'expiresAt': expiresAt.toIso8601String(),
      };
}

/// Pedido da TV para trocar o código por um token (`POST /api/v1/pair`).
final class PairRequest {
  const PairRequest({required this.code, required this.deviceInfo});

  factory PairRequest.fromJson(Map<String, Object?> json) => PairRequest(
        code: json.field<String>('code'),
        deviceInfo: DeviceInfo.fromJson(
          json.field<Map<String, Object?>>('deviceInfo'),
        ),
      );

  final String code;
  final DeviceInfo deviceInfo;

  Map<String, Object?> toJson() => {
        'code': code,
        'deviceInfo': deviceInfo.toJson(),
      };
}

/// Resposta do pareamento: as credenciais da TV.
///
/// O [deviceToken] só aparece nesta resposta. O servidor guarda apenas o
/// hash, então ele não pode ser recuperado depois.
final class PairResponse {
  const PairResponse({
    required this.deviceId,
    required this.deviceToken,
    required this.serverId,
  });

  factory PairResponse.fromJson(Map<String, Object?> json) => PairResponse(
        deviceId: json.field<String>('deviceId'),
        deviceToken: json.field<String>('deviceToken'),
        serverId: json.field<String>('serverId'),
      );

  final String deviceId;
  final String deviceToken;

  /// Identifica o servidor. A TV não reaproveita o token com outro servidor.
  final String serverId;

  Map<String, Object?> toJson() => {
        'deviceId': deviceId,
        'deviceToken': deviceToken,
        'serverId': serverId,
      };

  @override
  String toString() => 'PairResponse($deviceId, server: $serverId)';
}
