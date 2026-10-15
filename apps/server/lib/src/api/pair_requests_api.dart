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
import '../pairing/pair_requests.dart';
import '../realtime/device_hub.dart';

final _log = Logger('pairing');

/// Pareamento por aprovação no painel: a TV pede, o administrador aprova.
///
/// TV (sem sessão):
/// - `POST /api/v1/pair-requests`: abre o pedido; cada IP pode abrir
///   [maxCreateAttempts] por minuto.
/// - `GET /api/v1/pair-requests/<id>` com `Authorization: Bearer <secret>`:
///   situação do pedido e, uma única vez, as credenciais.
/// - `DELETE /api/v1/pair-requests/<id>` com o mesmo Bearer: desiste.
///
/// Painel (admin):
/// - `GET /api/v1/pair-requests`: pedidos pendentes.
/// - `POST /api/v1/pair-requests/<id>/approve` e `/reject`.
class PairRequestsApi {
  PairRequestsApi({
    required SessionStore sessions,
    required PairRequestStore requests,
    required DeviceStore devices,
    required DeviceHub hub,
    RateLimiter? createLimiter,
  }) : _sessions = sessions,
       _requests = requests,
       _devices = devices,
       _hub = hub,
       _createLimiter =
           createLimiter ??
           RateLimiter(
             maxAttempts: maxCreateAttempts,
             window: const Duration(minutes: 1),
           );

  static const maxCreateAttempts = 5;

  final SessionStore _sessions;
  final PairRequestStore _requests;
  final DeviceStore _devices;
  final DeviceHub _hub;
  final RateLimiter _createLimiter;

  void addRoutes(Router router) {
    final admin = const Pipeline().addMiddleware(_sessions.requireAdmin());
    router
      ..post('/api/v1/pair-requests', _create)
      ..get('/api/v1/pair-requests', admin.addHandler(_list))
      ..get('/api/v1/pair-requests/<id>', _poll)
      ..delete('/api/v1/pair-requests/<id>', _cancel)
      ..post('/api/v1/pair-requests/<id>/approve', admin.addHandler(_approve))
      ..post('/api/v1/pair-requests/<id>/reject', admin.addHandler(_reject));
  }

  Future<Response> _create(Request request) async {
    final ip = clientIp(request);
    _createLimiter.consume(ip);

    final DeviceInfo info;
    try {
      final raw = (await readJsonObject(request))['deviceInfo'];
      if (raw is! Map<String, Object?>) {
        throw const ProtocolException('campo "deviceInfo" ausente ou inválido');
      }
      info = DeviceInfo.fromJson(raw);
    } on ProtocolException catch (e) {
      throw ApiException.badRequest('Pedido inválido: ${e.message}.');
    }

    final PairRequestTicket ticket;
    final PairRequestEntry entry;
    final String? replaced;
    try {
      (ticket, entry, replaced) = _requests.create(info, ip);
    } on TooManyPairRequests {
      throw const ApiException(
        429,
        'too_many_pair_requests',
        'Há TVs demais aguardando aprovação. Aprove ou recuse as do painel '
            'e tente de novo.',
      );
    }
    if (replaced != null) _closed(replaced);
    _hub.publish(MessageTypes.pairRequestCreated, entry.toPending().toJson());
    _log.info(
      LogEvent('TV pediu aprovação', {
        'request': entry.id,
        'name': info.suggestedName,
        'ip': ip,
      }),
    );
    return jsonResponse(ticket.toJson(), status: 201);
  }

  Response _list(Request request) => jsonResponse({
    'requests': [for (final p in _requests.pending()) p.toJson()],
  });

  Response _poll(Request request) =>
      jsonResponse(_requests.poll(_forTv(request)).toJson());

  Response _cancel(Request request) {
    final entry = _forTv(request);
    if (_requests.remove(entry)) _closed(entry.id);
    return Response(204);
  }

  Response _approve(Request request) {
    final entry = _open(request);
    final deviceId = generateId();
    final token = generateToken();
    final name = entry.deviceInfo.suggestedName;
    _devices.create(
      id: deviceId,
      name: name,
      tokenHash: hashToken(token),
      info: entry.deviceInfo,
    );
    _requests.approve(
      entry,
      PairResponse(
        deviceId: deviceId,
        deviceToken: token,
        serverId: _devices.serverId,
      ),
    );
    _closed(entry.id);

    final row = _devices.find(deviceId)!;
    final summary = _hub.summaryOf(row).toJson();
    _hub.publish(MessageTypes.devicePaired, summary);
    _log.info(
      LogEvent('TV aprovada', {
        'deviceId': deviceId,
        'name': name,
        'ip': entry.ip,
      }),
    );
    return jsonResponse(summary);
  }

  Response _reject(Request request) {
    final entry = _open(request);
    _requests.reject(entry);
    _closed(entry.id);
    _log.info(LogEvent('TV recusada', {'request': entry.id, 'ip': entry.ip}));
    return Response(204);
  }

  /// Pedido aberto da rota, para o painel; `404` se não existe, venceu ou
  /// já foi decidido.
  PairRequestEntry _open(Request request) =>
      _requests.findOpen(request.params['id']!) ??
      (throw const ApiException.notFound(
        'Pedido não encontrado. Ele pode ter vencido ou já ter sido decidido.',
      ));

  /// Pedido da rota, se o Bearer é o segredo da TV que o abriu. Segredo
  /// errado responde como pedido inexistente.
  PairRequestEntry _forTv(Request request) {
    final secret = bearerTokenOf(request);
    final entry = secret == null
        ? null
        : _requests.findForTv(request.params['id']!, secret);
    return entry ??
        (throw const ApiException.notFound('Pedido não encontrado.'));
  }

  void _closed(String id) =>
      _hub.publish(MessageTypes.pairRequestClosed, {'id': id});
}
