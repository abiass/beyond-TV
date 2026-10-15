import 'dart:io';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';

import 'api/auth_api.dart';
import 'api/devices_api.dart';
import 'api/groups_api.dart';
import 'api/media_api.dart';
import 'api/pairing_api.dart';
import 'api/playlists_api.dart';
import 'api/schedules_api.dart';
import 'api/setup_api.dart';
import 'auth/admins.dart';
import 'auth/passwords.dart';
import 'auth/sessions.dart';
import 'clock.dart';
import 'devices/devices.dart';
import 'groups/group_store.dart';
import 'http/json.dart';
import 'http/middleware.dart';
import 'http/rate_limit.dart';
import 'http/static_site.dart';
import 'media/media_files.dart';
import 'media/media_store.dart';
import 'pairing/pairing_codes.dart';
import 'playlists/playlist_store.dart';
import 'realtime/admin_socket.dart';
import 'realtime/content_sync.dart';
import 'realtime/device_hub.dart';
import 'realtime/device_socket.dart';
import 'schedules/schedule_store.dart';

/// Versão do servidor exposta em `/health`.
const serverVersion = '0.1.0';

/// Monta o handler HTTP completo do servidor.
///
/// As rotas da API ficam em `/health`, `/api/` e `/ws/`. O resto é o
/// dashboard, servido de [webDir] quando a pasta existe. Os arquivos de
/// imagem e vídeo ficam em [mediaDir].
Handler buildHandler({
  required Database db,
  required String mediaDir,
  String? webDir,
  PasswordHasher hasher = const PasswordHasher(),
  Clock clock = DateTime.now,
  RealtimeTimeouts timeouts = const RealtimeTimeouts(),
}) {
  final Handler site = switch (webDir) {
    final dir? when Directory(dir).existsSync() => staticSiteHandler(dir),
    final dir? =>
      (request) => request.url.path.isEmpty
          ? dashboardMissing(dir)
          : throw const ApiException.notFound(),
    null => (_) => throw const ApiException.notFound(),
  };

  final router = Router(
    notFoundHandler: (request) => _isApiPath(request.url.path)
        ? throw const ApiException.notFound()
        : site(request),
  )..get('/health', _health);

  final admins = AdminStore(db);
  final sessions = SessionStore(db, clock: clock);
  SetupApi(
    admins: admins,
    sessions: sessions,
    hasher: hasher,
  ).addRoutes(router);
  AuthApi(
    admins: admins,
    sessions: sessions,
    hasher: hasher,
    loginLimiter: RateLimiter(
      maxAttempts: AuthApi.maxFailedLogins,
      window: const Duration(minutes: 1),
      clock: clock,
    ),
  ).addRoutes(router);
  final devices = DeviceStore(db, clock: clock);
  final media = MediaStore(db, clock: clock);
  final playlists = PlaylistStore(db, media, clock: clock);
  final groups = GroupStore(db, clock: clock);
  final schedules = ScheduleStore(db, clock: clock);
  final files = MediaFiles(mediaDir);
  final hub = DeviceHub(
    devices: devices,
    media: media,
    playlists: playlists,
    clock: clock,
  );
  final sync = ContentSync(
    devices: devices,
    groups: groups,
    schedules: schedules,
    media: media,
    playlists: playlists,
    hub: hub,
  );
  PairingApi(
    sessions: sessions,
    codes: PairingCodeStore(clock: clock),
    devices: devices,
    hub: hub,
    pairLimiter: RateLimiter(
      maxAttempts: PairingApi.maxPairAttempts,
      window: const Duration(minutes: 1),
      clock: clock,
    ),
  ).addRoutes(router);
  DevicesApi(
    sessions: sessions,
    devices: devices,
    groups: groups,
    media: media,
    playlists: playlists,
    hub: hub,
    sync: sync,
  ).addRoutes(router);
  MediaApi(
    sessions: sessions,
    media: media,
    files: files,
    devices: devices,
    hub: hub,
    sync: sync,
  ).addRoutes(router);
  PlaylistsApi(
    sessions: sessions,
    playlists: playlists,
    media: media,
    devices: devices,
    hub: hub,
    sync: sync,
  ).addRoutes(router);
  GroupsApi(
    sessions: sessions,
    groups: groups,
    devices: devices,
    media: media,
    playlists: playlists,
    hub: hub,
    sync: sync,
  ).addRoutes(router);
  SchedulesApi(
    sessions: sessions,
    schedules: schedules,
    playlists: playlists,
    devices: devices,
    groups: groups,
    sync: sync,
  ).addRoutes(router);
  router
    ..get(
      WsPaths.device,
      DeviceSocket(
        devices: devices,
        hub: hub,
        sync: sync,
        timeouts: timeouts,
      ).handle,
    )
    ..get(WsPaths.admin, AdminSocket(sessions: sessions, hub: hub).handle);

  return const Pipeline()
      .addMiddleware(requestLogger())
      .addMiddleware(errorHandler())
      .addMiddleware(originCheck())
      .addHandler(router.call);
}

bool _isApiPath(String path) =>
    path == 'api' ||
    path.startsWith('api/') ||
    path == 'ws' ||
    path.startsWith('ws/');

Response _health(Request request) => jsonResponse({
  'status': 'ok',
  'version': serverVersion,
  'protocol': protocolVersion,
});
