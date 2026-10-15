import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/sessions.dart';
import 'content_choice.dart';
import '../devices/devices.dart';
import '../groups/group_store.dart';
import '../http/json.dart';
import '../logging.dart';
import '../media/media_validation.dart';
import '../media/media_store.dart';
import '../playlists/playlist_store.dart';
import '../realtime/content_sync.dart';
import '../realtime/device_hub.dart';

final _log = Logger('devices');

/// Rotas de TVs (todas de admin).
///
/// - `GET /api/v1/devices`: lista com o estado online.
/// - `PATCH /api/v1/devices/<id>`: renomeia e/ou muda o grupo (`groupId`).
/// - `DELETE /api/v1/devices/<id>`: remove e derruba o WebSocket da TV.
/// - `PUT /api/v1/devices/<id>/content`: define o que a TV exibe (site, imagem, vídeo ou playlist).
/// - `POST /api/v1/devices/<id>/commands`: `reload`, `identify` e `unpair`.
class DevicesApi {
  DevicesApi({
    required SessionStore sessions,
    required DeviceStore devices,
    required GroupStore groups,
    required MediaStore media,
    required PlaylistStore playlists,
    required DeviceHub hub,
    required ContentSync sync,
  }) : _sessions = sessions,
       _devices = devices,
       _groups = groups,
       _media = media,
       _playlists = playlists,
       _hub = hub,
       _sync = sync;

  final SessionStore _sessions;
  final DeviceStore _devices;
  final GroupStore _groups;
  final MediaStore _media;
  final PlaylistStore _playlists;
  final DeviceHub _hub;
  final ContentSync _sync;

  void addRoutes(Router router) {
    final admin = const Pipeline().addMiddleware(_sessions.requireAdmin());
    router
      ..get('/api/v1/devices', admin.addHandler(_list))
      ..patch('/api/v1/devices/<id>', admin.addHandler(_update))
      ..delete('/api/v1/devices/<id>', admin.addHandler(_delete))
      ..put('/api/v1/devices/<id>/content', admin.addHandler(_setContent))
      ..post('/api/v1/devices/<id>/commands', admin.addHandler(_command));
  }

  Response _list(Request request) => jsonResponse({
    'devices': [for (final s in _hub.summaries()) s.toJson()],
  });

  Future<Response> _update(Request request) async {
    final id = request.params['id']!;
    final body = await readJsonObject(request);
    final hasGroup = body.containsKey('groupId');
    final name = !hasGroup || body.containsKey('name')
        ? validateMediaName(body['name'])
        : null;
    int? groupId;
    if (hasGroup) {
      final value = body['groupId'];
      if (value != null && value is! int) {
        throw const ApiException.badRequest('Campo "groupId" inválido.');
      }
      groupId = value as int?;
      if (groupId != null && _groups.find(groupId) == null) {
        throw const ApiException(
          400,
          'unknown_group',
          'O grupo informado não existe.',
        );
      }
    }
    if (_devices.find(id) == null) throw _notFound;
    if (name != null) _devices.rename(id, name);
    if (hasGroup) {
      _devices.setGroup(id, groupId);
      _sync.syncOnline();
    }
    final summary = _hub.summaryOf(_devices.find(id)!);
    _hub.publish(MessageTypes.deviceState, summary.toJson());
    return jsonResponse(summary.toJson());
  }

  Response _delete(Request request) {
    _remove(request.params['id']!);
    return Response(204);
  }

  /// Apaga a TV, derruba o WebSocket (4401) e avisa os dashboards.
  void _remove(String id) {
    if (!_devices.delete(id)) throw _notFound;
    _hub.disconnect(id, WsCloseCodes.unauthorized);
    _hub.publish(MessageTypes.deviceRemoved, {'deviceId': id});
    _log.info(LogEvent('TV removida', {'deviceId': id}));
  }

  Future<Response> _setContent(Request request) async {
    final id = request.params['id']!;
    final body = await readJsonObject(request);
    if (_devices.find(id) == null) throw _notFound;
    final choice = parseContentChoice(
      body,
      media: _media,
      playlists: _playlists,
    );

    _devices.setContent(
      id,
      mediaId: choice.mediaId,
      playlistId: choice.playlistId,
    );
    _sync.syncOnline();
    final summary = _hub.summaryOf(_devices.find(id)!);
    _hub.publish(MessageTypes.deviceState, summary.toJson());
    return jsonResponse(summary.toJson());
  }

  Future<Response> _command(Request request) async {
    final id = request.params['id']!;
    final body = await readJsonObject(request);
    final row = _devices.find(id);
    if (row == null) throw _notFound;
    final type = body['type'];
    if (type is! String || !DeviceCommands.all.contains(type)) {
      throw const ApiException.badRequest('Comando desconhecido.');
    }
    final online = _hub.isOnline(id);
    if (!online && type != DeviceCommands.unpair) {
      throw const ApiException.conflict('device_offline', 'A TV está offline.');
    }

    switch (type) {
      case DeviceCommands.reload:
        _hub.send(
          id,
          Envelope.create(MessageTypes.cmdReload, payload: const {}),
        );
      case DeviceCommands.identify:
        _hub.send(
          id,
          Envelope.create(
            MessageTypes.cmdIdentify,
            payload: IdentifyPayload(name: row.name).toJson(),
          ),
        );
      case DeviceCommands.unpair:
        _hub.send(
          id,
          Envelope.create(MessageTypes.cmdUnpair, payload: const {}),
        );
        _remove(id);
    }
    _log.info(LogEvent('comando enviado', {'deviceId': id, 'type': type}));
    return Response(202);
  }

  static const _notFound = ApiException.notFound('TV não encontrada.');
}
