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

final _log = Logger('playlists');

/// Rotas de playlists (todas de admin).
///
/// - `GET/POST /api/v1/playlists`: lista e cria.
/// - `GET/PATCH/DELETE /api/v1/playlists/<id>`: lê, renomeia e apaga.
/// - `PUT /api/v1/playlists/<id>/items`: substitui os itens.
class PlaylistsApi {
  PlaylistsApi({
    required SessionStore sessions,
    required PlaylistStore playlists,
    required MediaStore media,
    required DeviceStore devices,
    required DeviceHub hub,
    required ContentSync sync,
  }) : _sessions = sessions,
       _playlists = playlists,
       _media = media,
       _devices = devices,
       _hub = hub,
       _sync = sync;

  final SessionStore _sessions;
  final PlaylistStore _playlists;
  final MediaStore _media;
  final DeviceStore _devices;
  final DeviceHub _hub;
  final ContentSync _sync;

  void addRoutes(Router router) {
    final admin = const Pipeline().addMiddleware(_sessions.requireAdmin());
    router
      ..get('/api/v1/playlists', admin.addHandler(_list))
      ..post('/api/v1/playlists', admin.addHandler(_create))
      ..get('/api/v1/playlists/<id>', admin.addHandler(_get))
      ..patch('/api/v1/playlists/<id>', admin.addHandler(_rename))
      ..put('/api/v1/playlists/<id>/items', admin.addHandler(_putItems))
      ..delete('/api/v1/playlists/<id>', admin.addHandler(_delete));
  }

  Response _list(Request request) => jsonResponse({
    'playlists': [for (final p in _playlists.list()) p.toJson()],
  });

  Future<Response> _create(Request request) async {
    final body = await readJsonObject(request);
    final name = validateMediaName(body['name']);
    final playlist = _playlists.create(name);
    _log.info(LogEvent('playlist criada', {'playlistId': playlist.id}));
    return jsonResponse(playlist.toJsonWith(const []), status: 201);
  }

  Response _get(Request request) => jsonResponse(_json(_find(request)));

  Future<Response> _rename(Request request) async {
    final id = request.params['id']!;
    final body = await readJsonObject(request);
    _find(request);
    _playlists.rename(id, validateMediaName(body['name']));
    // O nome não vai no manifesto: só o painel precisa saber.
    _publishStates(_devices.devicesShowingPlaylist(id));
    return jsonResponse(_json(_find(request)));
  }

  Future<Response> _putItems(Request request) async {
    final id = request.params['id']!;
    final body = await readJsonObject(request);
    _find(request);

    final raw = body['items'];
    if (raw is! List<Object?> || raw.length > maxPlaylistItems) {
      throw const ApiException.badRequest(
        'Informe "items" com até $maxPlaylistItems itens.',
      );
    }
    final items = <(String, int?)>[];
    for (final item in raw) {
      if (item is! Map<String, Object?>) {
        throw const ApiException.badRequest('Item de playlist inválido.');
      }
      final mediaId = item['mediaId'];
      if (mediaId is! String || _media.find(mediaId) == null) {
        throw const ApiException(
          400,
          'unknown_media',
          'Um dos itens usa uma mídia que não existe.',
        );
      }
      final duration = item['durationSeconds'];
      if (duration != null &&
          (duration is! int || !isValidItemDuration(duration))) {
        throw const ApiException(
          400,
          'invalid_duration',
          'A duração deve ser de $minItemDurationSeconds a '
              '$maxItemDurationSeconds segundos.',
        );
      }
      items.add((mediaId, duration as int?));
    }

    _playlists.replaceItems(id, items);
    _sync.syncDevices(_devices.devicesShowingPlaylist(id));
    return jsonResponse(_json(_find(request)));
  }

  Response _delete(Request request) {
    final id = request.params['id']!;
    _find(request);
    // Calcula antes de apagar: o SET NULL zera a coluna das TVs.
    final showing = _devices.devicesShowingPlaylist(id);
    _playlists.delete(id);
    _sync.syncDevices(showing);
    _publishStates(showing);
    _log.info(LogEvent('playlist removida', {'playlistId': id}));
    return Response(204);
  }

  void _publishStates(Iterable<String> deviceIds) {
    for (final deviceId in deviceIds) {
      final row = _devices.find(deviceId);
      if (row != null) {
        _hub.publish(MessageTypes.deviceState, _hub.summaryOf(row).toJson());
      }
    }
  }

  Map<String, Object?> _json(PlaylistRow playlist) =>
      playlist.toJsonWith(_playlists.itemsOf(playlist.id));

  PlaylistRow _find(Request request) =>
      _playlists.find(request.params['id']!) ??
      (throw const ApiException.notFound('Playlist não encontrada.'));
}
