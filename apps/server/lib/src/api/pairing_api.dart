import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/sessions.dart';
import '../auth/tokens.dart';
import '../devices/devices.dart';
import '../http/json.dart';
import '../http/rate_limit.dart';
import '../logging.dart';
import '../pairing/pairing_codes.dart';
import '../realtime/device_hub.dart';

final _log = Logger('pairing');

/// Rotas de pareamento das TVs.
///
/// - `POST /api/v1/pairing-codes` (admin): gera um código.
/// - `GET /api/v1/pairing-codes/<code>` (admin): situação do código, para o
///   dashboard saber quando a TV pareou.
/// - `POST /api/v1/pair` (TV): troca o código por um token. Cada IP pode
///   tentar [maxPairAttempts] vezes por minuto.
class PairingApi {
  PairingApi({
    required SessionStore sessions,
    required PairingCodeStore codes,
    required DeviceStore devices,
    required DeviceHub hub,
    RateLimiter? pairLimiter,
  }) : _sessions = sessions,
       _codes = codes,
       _devices = devices,
       _hub = hub,
       _pairLimiter =
           pairLimiter ??
           RateLimiter(
             maxAttempts: maxPairAttempts,
             window: const Duration(minutes: 1),
           );

  static const maxPairAttempts = 5;

  final SessionStore _sessions;
  final PairingCodeStore _codes;
  final DeviceStore _devices;
  final DeviceHub _hub;
  final RateLimiter _pairLimiter;

  void addRoutes(Router router) {
    final admin = const Pipeline().addMiddleware(_sessions.requireAdmin());
    router
      ..post('/api/v1/pairing-codes', admin.addHandler(_create))
      ..get('/api/v1/pairing-codes/<code>', admin.addHandler(_status))
      ..post('/api/v1/pair', _pair);
  }

  Response _create(Request request) =>
      jsonResponse(_codes.generate().toJson(), status: 201);

  Response _status(Request request) {
    final found = _codes.lookup(request.params['code']!);
    if (found == null) {
      throw const ApiException.notFound('Código não encontrado.');
    }
    final (entry, status) = found;
    final deviceId = entry.deviceId;
    return jsonResponse({
      'code': entry.code,
      'expiresAt': entry.expiresAt.toIso8601String(),
      'status': status.name,
      'deviceId': ?deviceId,
      if (deviceId != null) 'deviceName': ?_devices.nameOf(deviceId),
    });
  }

  Future<Response> _pair(Request request) async {
    final ip = clientIp(request);
    _pairLimiter.consume(ip);

    final PairRequest pair;
    try {
      pair = PairRequest.fromJson(await readJsonObject(request));
    } on ProtocolException catch (e) {
      throw ApiException.badRequest(
        'Pedido de pareamento inválido: ${e.message}.',
      );
    }

    final code = normalizePairingCode(pair.code);
    final deviceId = generateId();
    final result = isWellFormedPairingCode(code)
        ? _codes.redeem(code, deviceId: deviceId)
        : RedeemResult.invalid;
    switch (result) {
      case RedeemResult.invalid:
        throw invalidCode;
      case RedeemResult.expired:
        throw expiredCode;
      case RedeemResult.ok:
        break;
    }

    final token = generateToken();
    final name = pair.deviceInfo.suggestedName;
    _devices.create(
      id: deviceId,
      name: name,
      tokenHash: hashToken(token),
      info: pair.deviceInfo,
    );
    _pairLimiter.reset(ip);
    final row = _devices.find(deviceId);
    if (row != null) {
      _hub.publish(MessageTypes.devicePaired, _hub.summaryOf(row).toJson());
    }
    _log.info(
      LogEvent('TV pareada', {'deviceId': deviceId, 'name': name, 'ip': ip}),
    );

    return jsonResponse(
      PairResponse(
        deviceId: deviceId,
        deviceToken: token,
        serverId: _devices.serverId,
      ).toJson(),
      status: 201,
    );
  }

  static const invalidCode = ApiException(
    400,
    'invalid_code',
    'Código inválido. Confira o código exibido no painel.',
  );

  static const expiredCode = ApiException(
    400,
    'expired_code',
    'Código expirado. Gere um novo código no painel.',
  );
}
