import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/sessions.dart';
import '../devices/devices.dart';
import '../http/json.dart';
import '../logging.dart';
import '../media/media_store.dart';
import '../media/media_validation.dart';
import '../playlists/playlist_store.dart';
import '../realtime/content_sync.dart';
import '../realtime/device_hub.dart';

final _log = Logger('devices');

/// Rotas de TVs (todas de admin).
///
/// - `GET /api/v1/devices`: lista com o estado online.
/// - `PATCH /api/v1/devices/<id>`: renomeia.
/// - `DELETE /api/v1/devices/<id>`: remove e derruba o WebSocket da TV.
/// - `PUT /api/v1/devices/<id>/content`: define o que a TV exibe (site, imagem, vídeo ou playlist).
/// - `POST /api/v1/devices/<id>/commands`: `reload`, `identify` e `unpair`.
class DevicesApi {
  DevicesApi({
    required SessionStore sessions,
    required DeviceStore devices,
    required MediaStore media,
    required PlaylistStore playlists,
    required DeviceHub hub,
    required ContentSync sync,
  }) : _sessions = sessions,
       _devices = devices,
       _media = media,
       _playlists = playlists,
       _hub = hub,
       _sync = sync;

  final SessionStore _sessions;
  final DeviceStore _devices;
  final MediaStore _media;
  final PlaylistStore _playlists;
  final DeviceHub _hub;
  final ContentSync _sync;

  void addRoutes(Router router) {
    final admin = const Pipeline().addMiddleware(_sessions.requireAdmin());
    router
      ..get('/api/v1/devices', admin.addHandler(_list))
      ..patch('/api/v1/devices/<id>', admin.addHandler(_rename))
      ..delete('/api/v1/devices/<id>', admin.addHandler(_delete))
      ..put('/api/v1/devices/<id>/content', admin.addHandler(_setContent))
      ..post('/api/v1/devices/<id>/commands', admin.addHandler(_command));
  }

  Response _list(Request request) => jsonResponse({
    'devices': [for (final s in _hub.summaries()) s.toJson()],
  });

  Future<Response> _rename(Request request) async {
    final id = request.params['id']!;
    final body = await readJsonObject(request);
    final name = requireString(body, 'name').trim();
    if (name.runes.isEmpty || name.runes.length > 64) {
      throw const ApiException.badRequest(
        'O nome deve ter de 1 a 64 caracteres.',
      );
    }
    if (!_devices.rename(id, name)) throw _notFound;
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
    final hasMediaId = body.containsKey('mediaId');
    final hasUrl = body['url'] != null;
    final hasPlaylistId = body.containsKey('playlistId');
    if ([hasMediaId, hasUrl, hasPlaylistId].where((has) => has).length != 1) {
      throw const ApiException.badRequest(
        'Informe "mediaId", "url" ou "playlistId" (apenas um).',
      );
    }
    if (_devices.find(id) == null) throw _notFound;

    String? mediaId;
    String? playlistId;
    if (hasUrl) {
      final url = validateUrl(body['url']);
      final name = body['name'] == null
          ? null
          : validateMediaName(body['name']);
      mediaId =
          (_media.findByUrl(url) ?? _media.createUrl(url: url, name: name)).id;
    } else if (hasPlaylistId) {
      final value = body['playlistId'];
      if (value != null && value is! String) {
        throw const ApiException.badRequest('Campo "playlistId" inválido.');
      }
      if (value != null && _playlists.find(value as String) == null) {
        throw const ApiException.notFound('Playlist não encontrada.');
      }
      playlistId = value as String?;
    } else {
      final value = body['mediaId'];
      if (value != null && value is! String) {
        throw const ApiException.badRequest('Campo "mediaId" inválido.');
      }
      if (value != null && _media.find(value as String) == null) {
        throw const ApiException.notFound('Mídia não encontrada.');
      }
      mediaId = value as String?;
    }

    _devices.setContent(id, mediaId: mediaId, playlistId: playlistId);
    _sync.syncDevice(id);
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
