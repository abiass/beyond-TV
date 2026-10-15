import 'dart:typed_data';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('ScreenshotResult guarda os bytes em base64', () {
    final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0x00, 0x10]);
    final result = ScreenshotResult.fromBytes(
      requestId: 'r1',
      mime: 'image/jpeg',
      bytes: bytes,
    );

    final decoded = ScreenshotResult.fromJson(result.toJson());

    expect(decoded.requestId, 'r1');
    expect(decoded.mime, 'image/jpeg');
    expect(decoded.bytes, bytes);
    expect(decoded.toString(), isNot(contains(result.data)));
  });

  test('ScreenshotResult com base64 inválido lança ao ler os bytes', () {
    const result = ScreenshotResult(
      requestId: 'r1',
      mime: 'image/png',
      data: '%%%',
    );

    expect(() => result.bytes, throwsFormatException);
  });

  test('payloads simples fazem ida e volta', () {
    expect(
      ScreenshotRequest.fromJson(
        const ScreenshotRequest(requestId: 'r2').toJson(),
      ).requestId,
      'r2',
    );

    final error = ErrorPayload.fromJson(
      const ErrorPayload(
        ref: 'e1',
        code: 'capture_failed',
        message: 'Falhou.',
      ).toJson(),
    );
    expect(error.code, 'capture_failed');
    expect(error.ref, 'e1');

    final event = DeviceScreenshotEvent.fromJson(
      DeviceScreenshotEvent(
        deviceId: 'd1',
        capturedAt: DateTime.utc(2026, 10, 15, 12),
      ).toJson(),
    );
    expect(event.capturedAt, DateTime.utc(2026, 10, 15, 12));
  });

  test('AuditEntry faz ida e volta com campos opcionais nulos', () {
    final entry = AuditEntry(
      id: 7,
      at: DateTime.utc(2026, 10, 15),
      method: 'DELETE',
      path: '/api/v1/devices/abc',
      status: 204,
      adminId: 1,
      adminName: 'admin',
      ip: '192.168.0.10',
    );

    final decoded = AuditEntry.fromJson(entry.toJson());

    expect(decoded.path, entry.path);
    expect(decoded.status, 204);
    expect(decoded.adminName, 'admin');
    expect(
      AuditEntry.fromJson({...entry.toJson(), 'adminId': null}).adminId,
      isNull,
    );
  });

  test('screenshot é um comando aceito', () {
    expect(DeviceCommands.all, contains(DeviceCommands.screenshot));
  });
}
