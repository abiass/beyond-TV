import 'dart:typed_data';

import 'package:beyond_protocol/beyond_protocol.dart';

import '../auth/tokens.dart';
import '../clock.dart';
import '../http/rate_limit.dart';
import '../media/media_files.dart';

/// Última captura de tela de uma TV.
class Screenshot {
  const Screenshot({
    required this.bytes,
    required this.mime,
    required this.capturedAt,
  });

  final Uint8List bytes;
  final String mime;
  final DateTime capturedAt;
}

/// Capturas de tela só em memória: pedidos pendentes, intervalo mínimo entre
/// pedidos e a última imagem de cada TV.
///
/// A imagem pode mostrar dados reais dos dashboards, por isso nunca vai para
/// o disco nem para o log.
class ScreenshotStore {
  ScreenshotStore({Clock clock = DateTime.now}) : _clock = clock;

  /// Quanto tempo a TV tem para responder a um pedido.
  static const pendingTtl = Duration(seconds: 30);

  /// Tamanho máximo do texto base64 de uma captura de [maxScreenshotBytes].
  static const _maxBase64Length = (maxScreenshotBytes + 2) ~/ 3 * 4;

  final Clock _clock;
  final _pending = <String, Map<String, _Pending>>{};
  final _lastRequest = <String, DateTime>{};
  final _latest = <String, Screenshot>{};

  /// Registra um pedido para a TV [deviceId] e devolve o `requestId`.
  ///
  /// Lança [TooManyRequestsException] dentro do [screenshotCooldown].
  String begin(String deviceId) {
    final now = _clock();
    final last = _lastRequest[deviceId];
    if (last != null && now.difference(last) < screenshotCooldown) {
      throw TooManyRequestsException(
        last.add(screenshotCooldown).difference(now),
      );
    }
    _lastRequest[deviceId] = now;
    final byId = _pending.putIfAbsent(deviceId, () => {});
    byId.removeWhere((_, p) => _expired(p, now));
    final requestId = generateId();
    byId[requestId] = _Pending(now);
    return requestId;
  }

  /// Anota o id do envelope `cmd.screenshot` do pedido [requestId], que a TV
  /// cita no campo `ref` do `error`.
  void bindRef(String deviceId, String requestId, String ref) =>
      _pending[deviceId]?[requestId]?.ref = ref;

  /// Desfaz [begin] quando o comando não pôde ser enviado.
  void cancel(String deviceId, String requestId) {
    _pending[deviceId]?.remove(requestId);
    _lastRequest.remove(deviceId);
  }

  /// Remove o pedido da TV cujo `cmd.screenshot` tinha o id [ref].
  void dropByRef(String deviceId, String ref) =>
      _pending[deviceId]?.removeWhere((_, p) => p.ref == ref);

  /// Valida [result] da TV [deviceId] e, se estiver tudo certo, guarda a
  /// captura e encerra o pedido.
  ///
  /// Devolve o motivo da recusa, sem nada do conteúdo, ou `null` se aceitou.
  String? accept(String deviceId, ScreenshotResult result) {
    final pending = _pending[deviceId]?[result.requestId];
    if (pending == null) return 'unknown_request';
    if (_expired(pending, _clock())) {
      _pending[deviceId]?.remove(result.requestId);
      return 'expired_request';
    }
    if (!screenshotMimes.contains(result.mime)) return 'invalid_mime';
    if (result.data.length > _maxBase64Length) return 'too_large';
    final Uint8List bytes;
    try {
      bytes = result.bytes;
    } on FormatException {
      return 'invalid_base64';
    }
    if (bytes.isEmpty) return 'empty';
    if (bytes.length > maxScreenshotBytes) return 'too_large';
    final head = bytes.length > 16 ? bytes.sublist(0, 16) : bytes;
    if (MediaFiles.detectMime(head) != result.mime) return 'mime_mismatch';

    _pending[deviceId]?.remove(result.requestId);
    _latest[deviceId] = Screenshot(
      bytes: bytes,
      mime: result.mime,
      capturedAt: _clock().toUtc(),
    );
    return null;
  }

  /// Última captura da TV, se houver.
  Screenshot? latest(String deviceId) => _latest[deviceId];

  /// Esquece tudo sobre a TV (ao removê-la).
  void forget(String deviceId) {
    _pending.remove(deviceId);
    _lastRequest.remove(deviceId);
    _latest.remove(deviceId);
  }

  static bool _expired(_Pending p, DateTime now) =>
      now.difference(p.createdAt) >= pendingTtl;
}

class _Pending {
  _Pending(this.createdAt);

  final DateTime createdAt;
  String? ref;
}
