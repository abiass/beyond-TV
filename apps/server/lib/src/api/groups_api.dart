import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/sessions.dart';
import '../devices/devices.dart';
import '../groups/group_store.dart';
import '../http/json.dart';
import '../logging.dart';
import '../media/media_store.dart';
import '../media/media_validation.dart';
import '../playlists/playlist_store.dart';
import '../realtime/content_sync.dart';
import '../realtime/device_hub.dart';
import 'content_choice.dart';

final _log = Logger('groups');

/// Rotas de grupos de TVs (todas de admin).
///
/// - `GET/POST /api/v1/groups`: lista e cria.
/// - `PATCH/DELETE /api/v1/groups/<id>`: renomeia e apaga.
/// - `PUT /api/v1/groups/<id>/devices`: define os membros.
/// - `PUT /api/v1/groups/<id>/content`: define o conteúdo padrão do grupo.
class GroupsApi {
  GroupsApi({
    required SessionStore sessions,
    required GroupStore groups,
    required DeviceStore devices,
    required MediaStore media,
    required PlaylistStore playlists,
    required DeviceHub hub,
    required ContentSync sync,
  }) : _sessions = sessions,
       _groups = groups,
       _devices = devices,
       _media = media,
       _playlists = playlists,
       _hub = hub,
       _sync = sync;

  final SessionStore _sessions;
  final GroupStore _groups;
  final DeviceStore _devices;
  final MediaStore _media;
  final PlaylistStore _playlists;
  final DeviceHub _hub;
  final ContentSync _sync;

  void addRoutes(Router router) {
    final admin = const Pipeline().addMiddleware(_sessions.requireAdmin());
    router
      ..get('/api/v1/groups', admin.addHandler(_list))
      ..post('/api/v1/groups', admin.addHandler(_create))
      ..patch('/api/v1/groups/<id>', admin.addHandler(_rename))
      ..delete('/api/v1/groups/<id>', admin.addHandler(_delete))
      ..put('/api/v1/groups/<id>/devices', admin.addHandler(_setDevices))
      ..put('/api/v1/groups/<id>/content', admin.addHandler(_setContent));
  }

  Response _list(Request request) => jsonResponse({
    'groups': [for (final g in _groups.list()) _json(g)],
  });

  Future<Response> _create(Request request) async {
    final body = await readJsonObject(request);
    final name = validateMediaName(body['name']);
    _requireFreeName(name);
    final group = _groups.create(name);
    _log.info(LogEvent('grupo criado', {'groupId': group.id}));
    return jsonResponse(_json(group), status: 201);
  }

  Future<Response> _rename(Request request) async {
    final id = _id(request);
    final body = await readJsonObject(request);
    final name = validateMediaName(body['name']);
    _find(id);
    _requireFreeName(name, exceptId: id);
    _groups.rename(id, name);
    return jsonResponse(_json(_find(id)));
  }

  Response _delete(Request request) {
    final id = _id(request);
    final members = _find(id).deviceIds;
    _groups.delete(id);
    _sync.syncOnline();
    _publishStates(members);
    _log.info(LogEvent('grupo removido', {'groupId': id}));
    return Response(204);
  }

  Future<Response> _setDevices(Request request) async {
    final id = _id(request);
    final body = await readJsonObject(request);
    _find(id);
    final raw = body['deviceIds'];
    if (raw is! List<Object?> || raw.any((e) => e is! String)) {
      throw const ApiException.badRequest(
        'Informe "deviceIds" com uma lista de ids.',
      );
    }
    final ids = raw.cast<String>();
    if (ids.any((deviceId) => _devices.find(deviceId) == null)) {
      throw const ApiException(
        400,
        'unknown_device',
        'Uma das TVs informadas não existe.',
      );
    }
    final changed = _groups.setMembers(id, ids);
    _sync.syncOnline();
    _publishStates(changed);
    return jsonResponse(_json(_find(id)));
  }

  Future<Response> _setContent(Request request) async {
    final id = _id(request);
    final body = await readJsonObject(request);
    _find(id);
    final choice = parseContentChoice(
      body,
      media: _media,
      playlists: _playlists,
    );
    _groups.setContent(
      id,
      mediaId: choice.mediaId,
      playlistId: choice.playlistId,
    );
    _sync.syncOnline();
    return jsonResponse(_json(_find(id)));
  }

  void _publishStates(Iterable<String> deviceIds) {
    for (final deviceId in deviceIds) {
      final row = _devices.find(deviceId);
      if (row != null) {
        _hub.publish(MessageTypes.deviceState, _hub.summaryOf(row).toJson());
      }
    }
  }

  void _requireFreeName(String name, {int? exceptId}) {
    if (_groups.nameTaken(name, exceptId: exceptId)) {
      throw const ApiException.conflict(
        'name_taken',
        'Já existe um grupo com esse nome.',
      );
    }
  }

  /// Formato `Group` do protocolo.
  Map<String, Object?> _json(GroupRow group) {
    final mediaId = group.mediaId;
    final media = mediaId == null ? null : _media.find(mediaId);
    final playlistId = group.playlistId;
    final playlist = playlistId == null ? null : _playlists.find(playlistId);
    return {
      'id': group.id,
      'name': group.name,
      'deviceIds': group.deviceIds,
      'content': media?.toContentItem().toJson(),
      'playlist': playlist == null
          ? null
          : PlaylistRef(id: playlist.id, name: playlist.name).toJson(),
      'createdAt': group.createdAt.toIso8601String(),
    };
  }

  int _id(Request request) =>
      int.tryParse(request.params['id']!) ?? (throw _notFound);

  GroupRow _find(int id) => _groups.find(id) ?? (throw _notFound);

  static const _notFound = ApiException.notFound('Grupo não encontrado.');
}
