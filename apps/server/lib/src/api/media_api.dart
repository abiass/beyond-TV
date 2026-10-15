import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/sessions.dart';
import '../auth/tokens.dart';
import '../devices/devices.dart';
import '../http/json.dart';
import '../logging.dart';
import '../media/media_files.dart';
import '../media/media_store.dart';
import '../media/media_validation.dart';
import '../playlists/playlist_store.dart';
import '../realtime/content_sync.dart';
import '../realtime/device_hub.dart';

final _log = Logger('media');

/// Rotas da biblioteca de mídia (todas de admin).
///
/// - `GET /api/v1/media`: lista.
/// - `POST /api/v1/media`: cadastra um site.
/// - `POST /api/v1/media/files?name=`: envia imagem ou vídeo (corpo cru).
/// - `GET /api/v1/media/<id>/file`: baixa o arquivo (admin ou TV).
/// - `PATCH /api/v1/media/<id>`: altera nome e/ou URL e atualiza as TVs.
/// - `DELETE /api/v1/media/<id>`: apaga, tira das playlists e atualiza as TVs.
class MediaApi {
  MediaApi({
    required SessionStore sessions,
    required MediaStore media,
    required MediaFiles files,
    required PlaylistStore playlists,
    required DeviceStore devices,
    required DeviceHub hub,
    required ContentSync sync,
  }) : _sessions = sessions,
       _media = media,
       _files = files,
       _playlists = playlists,
       _devices = devices,
       _hub = hub,
       _sync = sync;

  final SessionStore _sessions;
  final MediaStore _media;
  final MediaFiles _files;
  final PlaylistStore _playlists;
  final DeviceStore _devices;
  final DeviceHub _hub;
  final ContentSync _sync;

  void addRoutes(Router router) {
    final admin = const Pipeline().addMiddleware(_sessions.requireAdmin());
    router
      ..get('/api/v1/media', admin.addHandler(_list))
      ..post('/api/v1/media', admin.addHandler(_create))
      ..post('/api/v1/media/files', admin.addHandler(_upload))
      ..get('/api/v1/media/<id>/file', _download)
      ..patch('/api/v1/media/<id>', admin.addHandler(_update))
      ..delete('/api/v1/media/<id>', admin.addHandler(_delete));
  }

  Response _list(Request request) => jsonResponse({
    'media': [for (final m in _media.list()) m.toJson()],
  });

  Future<Response> _create(Request request) async {
    final body = await readJsonObject(request);
    if (body['kind'] != MediaKinds.url) {
      throw const ApiException.badRequest(
        'Por enquanto só sites (kind = url).',
      );
    }
    final url = validateUrl(body['url']);
    final name = body['name'] == null ? null : validateMediaName(body['name']);
    final media = _media.createUrl(url: url, name: name);
    _log.info(LogEvent('mídia criada', {'mediaId': media.id}));
    return jsonResponse(media.toJson(), status: 201);
  }

  /// Recebe o arquivo em streaming (sem o limite de 64 KiB do JSON).
  Future<Response> _upload(Request request) async {
    final rawName = request.url.queryParameters['name'];
    final name = rawName == null ? null : validateMediaName(rawName);
    final stored = await _files.store(
      request.read(),
      declaredMime: request.headers['content-type'] ?? '',
      contentLength: request.contentLength,
    );
    final existing = _media.findBySha256(stored.sha256);
    if (existing != null) return jsonResponse(existing.toJson());
    final media = _media.createFile(
      kind: stored.kind,
      name: name ?? (stored.kind == MediaKinds.video ? 'Vídeo' : 'Imagem'),
      sha256: stored.sha256,
      sizeBytes: stored.sizeBytes,
      mime: stored.mime,
    );
    _log.info(LogEvent('arquivo enviado', {'mediaId': media.id}));
    return jsonResponse(media.toJson(), status: 201);
  }

  /// Aceita a sessão do admin ou o token de uma TV pareada.
  Future<Response> _download(Request request) async {
    final session = SessionStore.tokenOf(request);
    final bearer = bearerTokenOf(request);
    final allowed =
        (session != null && _sessions.findAdmin(session) != null) ||
        (bearer != null && _devices.findByTokenHash(hashToken(bearer)) != null);
    if (!allowed) throw const ApiException.unauthorized();

    final media = _media.find(request.params['id']!);
    final sha256 = media?.sha256;
    final file = sha256 == null ? null : _files.fileFor(sha256);
    if (media == null || file == null || !file.existsSync()) throw _notFound;

    final etag = '"$sha256"';
    final headers = {
      'etag': etag,
      'cache-control': 'private, max-age=31536000, immutable',
      // O navegador não pode reinterpretar o arquivo como HTML.
      'x-content-type-options': 'nosniff',
    };
    final ifNoneMatch = request.headers['if-none-match'];
    if (ifNoneMatch != null &&
        ifNoneMatch
            .split(',')
            .map((tag) => tag.trim().replaceFirst(RegExp('^W/'), ''))
            .any((tag) => tag == etag || tag == '*')) {
      return Response(304, headers: headers);
    }
    return Response.ok(
      file.openRead(),
      headers: {
        ...headers,
        'content-type': media.mime!,
        'content-length': '${await file.length()}',
      },
    );
  }

  Future<Response> _update(Request request) async {
    final id = request.params['id']!;
    final body = await readJsonObject(request);
    final current = _media.find(id);
    if (current == null) throw _notFound;
    if (current.kind != MediaKinds.url && body['url'] != null) {
      throw const ApiException.badRequest(
        'Só o nome de imagens e vídeos pode ser alterado.',
      );
    }
    final name = body['name'] == null ? null : validateMediaName(body['name']);
    final url = body['url'] == null ? null : validateUrl(body['url']);
    final media = _media.update(id, name: name, url: url)!;
    _refresh(id);
    return jsonResponse(media.toJson());
  }

  Future<Response> _delete(Request request) async {
    final id = request.params['id']!;
    final current = _media.find(id);
    if (current == null) throw _notFound;
    // Calcula antes de apagar: o CASCADE tira a mídia das playlists.
    final direct = _devices.devicesShowing(id);
    final viaPlaylist = _viaPlaylist(id);
    _media.delete(id);
    final sha256 = current.sha256;
    if (sha256 != null) {
      await _files.deleteIfUnused(sha256, _media.isSha256InUse);
    }
    _notify(direct, viaPlaylist);
    _log.info(LogEvent('mídia removida', {'mediaId': id}));
    return Response(204);
  }

  /// TVs que exibem a mídia dentro de uma playlist.
  Set<String> _viaPlaylist(String mediaId) => {
    for (final playlistId in _playlists.playlistsContaining(mediaId))
      ..._devices.devicesShowingPlaylist(playlistId),
  };

  void _refresh(String mediaId) =>
      _notify(_devices.devicesShowing(mediaId), _viaPlaylist(mediaId));

  /// Manda `content.sync` a todas as TVs afetadas e `device.state` às que
  /// exibem a mídia avulsa (o resumo das outras não muda).
  void _notify(Iterable<String> direct, Iterable<String> viaPlaylist) {
    _sync.syncDevices({...direct, ...viaPlaylist});
    for (final deviceId in direct) {
      final row = _devices.find(deviceId);
      if (row != null) {
        _hub.publish(MessageTypes.deviceState, _hub.summaryOf(row).toJson());
      }
    }
  }

  static const _notFound = ApiException.notFound('Mídia não encontrada.');
}
