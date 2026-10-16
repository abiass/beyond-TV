import 'device_info.dart';
import 'json_fields.dart';
import 'pairing.dart';
import 'protocol_exception.dart';

/// Validade de um pedido de aprovação feito pela TV.
const pairRequestTtl = Duration(minutes: 10);

/// Dígitos do código de conferência que aparece na TV e no painel.
const confirmCodeLength = 4;

/// Intervalo com que a TV pergunta se o pedido já foi aprovado.
const pairRequestPollInterval = Duration(seconds: 2);

/// Resposta a `POST /api/v1/pair-requests`: o pedido que a TV acabou de
/// abrir.
///
/// [secret] só aparece aqui e autoriza a TV a consultar e cancelar o pedido
/// (`Authorization: Bearer <secret>`). [confirmCode] é mostrado na TV para
/// o administrador conferir que aprova a TV certa.
final class PairRequestTicket {
  PairRequestTicket({
    required this.id,
    required this.secret,
    required this.confirmCode,
    required DateTime expiresAt,
  }) : expiresAt = expiresAt.toUtc();

  factory PairRequestTicket.fromJson(Map<String, Object?> json) =>
      PairRequestTicket(
        id: json.field<String>('id'),
        secret: json.field<String>('secret'),
        confirmCode: json.field<String>('confirmCode'),
        expiresAt: json.dateField('expiresAt'),
      );

  final String id;
  final String secret;
  final String confirmCode;
  final DateTime expiresAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'secret': secret,
        'confirmCode': confirmCode,
        'expiresAt': expiresAt.toIso8601String(),
      };

  @override
  String toString() => 'PairRequestTicket($id, $confirmCode)';
}

/// Situação de um pedido de aprovação.
enum PairRequestStatus { pending, approved, rejected, expired }

/// Resposta a `GET /api/v1/pair-requests/:id` (TV).
///
/// Com [PairRequestStatus.approved], traz as [credentials]; o servidor só as
/// entrega uma vez e então esquece o pedido.
final class PairRequestPoll {
  const PairRequestPoll(this.status, {this.credentials});

  factory PairRequestPoll.fromJson(Map<String, Object?> json) {
    final name = json.field<String>('status');
    final status =
        PairRequestStatus.values.where((s) => s.name == name).firstOrNull;
    if (status == null) {
      throw ProtocolException('campo "status" inválido: "$name"');
    }
    return PairRequestPoll(
      status,
      credentials: status == PairRequestStatus.approved
          ? PairResponse.fromJson(json)
          : null,
    );
  }

  final PairRequestStatus status;
  final PairResponse? credentials;

  Map<String, Object?> toJson() => {
        'status': status.name,
        ...?credentials?.toJson(),
      };
}

/// Pedido aguardando aprovação, como o painel vê
/// (`GET /api/v1/pair-requests` e evento `pair_request.created`).
final class PendingPairRequest {
  PendingPairRequest({
    required this.id,
    required this.confirmCode,
    required this.deviceInfo,
    required this.ip,
    required DateTime createdAt,
    required DateTime expiresAt,
  })  : createdAt = createdAt.toUtc(),
        expiresAt = expiresAt.toUtc();

  factory PendingPairRequest.fromJson(Map<String, Object?> json) =>
      PendingPairRequest(
        id: json.field<String>('id'),
        confirmCode: json.field<String>('confirmCode'),
        deviceInfo: DeviceInfo.fromJson(
          json.field<Map<String, Object?>>('deviceInfo'),
        ),
        ip: json.field<String>('ip'),
        createdAt: json.dateField('createdAt'),
        expiresAt: json.dateField('expiresAt'),
      );

  final String id;
  final String confirmCode;
  final DeviceInfo deviceInfo;

  /// IP de onde a TV fez o pedido.
  final String ip;
  final DateTime createdAt;
  final DateTime expiresAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'confirmCode': confirmCode,
        'deviceInfo': deviceInfo.toJson(),
        'ip': ip,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
      };
}
