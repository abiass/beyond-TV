import 'dart:convert';
import 'dart:typed_data';

import 'json_fields.dart';

/// Tamanho máximo de uma captura de tela, depois de decodificada.
const maxScreenshotBytes = 2 * 1024 * 1024;

/// Largura máxima da captura; a TV reduz mantendo a proporção.
const screenshotMaxWidth = 1280;

/// Intervalo mínimo entre capturas da mesma TV.
const screenshotCooldown = Duration(seconds: 5);

/// MIME aceitos numa captura.
const screenshotMimes = {'image/jpeg', 'image/png'};

/// Largura dos quadros do controle ao vivo: menor, para chegarem rápido.
const liveFrameMaxWidth = 960;

/// Intervalo mínimo entre quadros do controle ao vivo da mesma TV.
const liveFrameCooldown = Duration(milliseconds: 100);

/// Payload do `cmd.screenshot`: o servidor pede uma captura.
final class ScreenshotRequest {
  const ScreenshotRequest({required this.requestId, this.maxWidth});

  factory ScreenshotRequest.fromJson(Map<String, Object?> json) =>
      ScreenshotRequest(
        requestId: json.field<String>('requestId'),
        maxWidth: json.optionalField<int>('maxWidth'),
      );

  final String requestId;

  /// Largura máxima pedida; sem ela, [screenshotMaxWidth].
  final int? maxWidth;

  Map<String, Object?> toJson() => {
        'requestId': requestId,
        if (maxWidth != null) 'maxWidth': maxWidth,
      };
}

/// Payload do `screenshot.result`: a imagem em base64.
final class ScreenshotResult {
  const ScreenshotResult({
    required this.requestId,
    required this.mime,
    required this.data,
  });

  factory ScreenshotResult.fromBytes({
    required String requestId,
    required String mime,
    required Uint8List bytes,
  }) =>
      ScreenshotResult(
        requestId: requestId,
        mime: mime,
        data: base64Encode(bytes),
      );

  factory ScreenshotResult.fromJson(Map<String, Object?> json) =>
      ScreenshotResult(
        requestId: json.field<String>('requestId'),
        mime: json.field<String>('mime'),
        data: json.field<String>('data'),
      );

  final String requestId;

  /// Um de [screenshotMimes].
  final String mime;

  /// Imagem em base64 (padrão, com `=`).
  final String data;

  /// Os bytes da imagem. Lança [FormatException] se [data] não é base64.
  Uint8List get bytes => base64Decode(data);

  Map<String, Object?> toJson() => {
        'requestId': requestId,
        'mime': mime,
        'data': data,
      };

  @override
  String toString() => 'ScreenshotResult($requestId, $mime)';
}

/// Payload do `error`: a TV não conseguiu atender a mensagem [ref].
final class ErrorPayload {
  const ErrorPayload({
    required this.ref,
    required this.code,
    required this.message,
  });

  factory ErrorPayload.fromJson(Map<String, Object?> json) => ErrorPayload(
        ref: json.field<String>('ref'),
        code: json.field<String>('code'),
        message: json.field<String>('message'),
      );

  /// `id` do envelope que falhou.
  final String ref;
  final String code;
  final String message;

  Map<String, Object?> toJson() => {
        'ref': ref,
        'code': code,
        'message': message,
      };
}

/// Payload do evento `device.screenshot` para o painel: há captura nova.
final class DeviceScreenshotEvent {
  DeviceScreenshotEvent({required this.deviceId, required DateTime capturedAt})
      : capturedAt = capturedAt.toUtc();

  factory DeviceScreenshotEvent.fromJson(Map<String, Object?> json) =>
      DeviceScreenshotEvent(
        deviceId: json.field<String>('deviceId'),
        capturedAt: json.dateField('capturedAt'),
      );

  final String deviceId;
  final DateTime capturedAt;

  Map<String, Object?> toJson() => {
        'deviceId': deviceId,
        'capturedAt': capturedAt.toIso8601String(),
      };
}

/// Uma linha do log de auditoria (`GET /api/v1/audit`).
final class AuditEntry {
  AuditEntry({
    required this.id,
    required DateTime at,
    required this.method,
    required this.path,
    required this.status,
    this.adminId,
    this.adminName,
    this.ip,
  }) : at = at.toUtc();

  factory AuditEntry.fromJson(Map<String, Object?> json) => AuditEntry(
        id: json.field<int>('id'),
        at: json.dateField('at'),
        method: json.field<String>('method'),
        path: json.field<String>('path'),
        status: json.field<int>('status'),
        adminId: json.optionalField<int>('adminId'),
        adminName: json.optionalField<String>('adminName'),
        ip: json.optionalField<String>('ip'),
      );

  final int id;
  final DateTime at;

  /// Método HTTP (`POST`, `PUT`, `PATCH` ou `DELETE`).
  final String method;

  /// Caminho sem query string, ex.: `/api/v1/devices/abc/content`.
  final String path;

  /// Status HTTP da resposta.
  final int status;

  /// Admin da sessão; `null` em login, setup ou sessão inválida.
  final int? adminId;
  final String? adminName;

  /// IP de origem da requisição.
  final String? ip;

  Map<String, Object?> toJson() => {
        'id': id,
        'at': at.toIso8601String(),
        'method': method,
        'path': path,
        'status': status,
        'adminId': adminId,
        'adminName': adminName,
        'ip': ip,
      };
}
