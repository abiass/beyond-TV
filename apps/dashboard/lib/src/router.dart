import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'audit/audit_page.dart';
import 'auth/auth_controller.dart';
import 'devices/device_detail_page.dart';
import 'devices/live_control_page.dart';
import 'groups/group_detail_page.dart';
import 'groups/groups_page.dart';
import 'media/media_library_page.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'pages/setup_page.dart';
import 'pages/startup_page.dart';
import 'playlists/playlist_editor_page.dart';
import 'playlists/playlists_page.dart';
import 'schedules/schedule_page.dart';

/// Rotas do dashboard.
abstract final class Routes {
  static const startup = '/carregando';
  static const setup = '/configuracao';
  static const login = '/login';
  static const home = '/';

  /// Detalhes da TV [id].
  static String device(String id) => '/tvs/$id';

  /// Controle ao vivo da TV [id].
  static String liveControl(String id) => '/tvs/$id/controle';

  static const media = '/midia';
  static const playlists = '/playlists';

  /// Editor da playlist [id].
  static String playlist(String id) => '/playlists/$id';

  static const groups = '/grupos';

  /// Detalhes do grupo [id].
  static String group(int id) => '/grupos/$id';

  static const audit = '/auditoria';

  static const schedule = '/agenda';

  /// Agenda semanal de uma TV ([deviceId]) ou de um grupo ([groupId]).
  static String scheduleFor({String? deviceId, int? groupId}) => Uri(
        path: schedule,
        queryParameters: {
          if (deviceId != null) 'deviceId': deviceId,
          if (groupId != null) 'groupId': '$groupId',
        },
      ).toString();
}

/// Roteador que leva cada estado de autenticação para a tela certa.
final routerProvider = Provider<GoRouter>((ref) {
  final auth = ValueNotifier<AsyncValue<AuthState>>(const AsyncLoading());
  ref
    ..listen(
      authProvider,
      (_, next) => auth.value = next,
      fireImmediately: true,
    )
    ..onDispose(auth.dispose);

  final router = GoRouter(
    initialLocation: Routes.home,
    refreshListenable: auth,
    redirect: (context, state) =>
        redirectFor(auth.value, state.matchedLocation),
    routes: [
      GoRoute(
        path: Routes.startup,
        builder: (context, state) => const StartupPage(),
      ),
      GoRoute(
        path: Routes.setup,
        builder: (context, state) => const SetupPage(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: '/tvs/:id',
        builder: (context, state) =>
            DeviceDetailPage(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/tvs/:id/controle',
        builder: (context, state) =>
            LiveControlPage(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.media,
        builder: (context, state) => const MediaLibraryPage(),
      ),
      GoRoute(
        path: Routes.playlists,
        builder: (context, state) => const PlaylistsPage(),
      ),
      GoRoute(
        path: '/playlists/:id',
        builder: (context, state) =>
            PlaylistEditorPage(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.groups,
        builder: (context, state) => const GroupsPage(),
      ),
      GoRoute(
        path: '/grupos/:id',
        builder: (context, state) => GroupDetailPage(
          id: int.tryParse(state.pathParameters['id']!) ?? -1,
        ),
      ),
      GoRoute(
        path: Routes.audit,
        builder: (context, state) => const AuditPage(),
      ),
      GoRoute(
        path: Routes.schedule,
        builder: (context, state) => SchedulePage(
          deviceId: state.uri.queryParameters['deviceId'],
          groupId: int.tryParse(state.uri.queryParameters['groupId'] ?? ''),
        ),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Para onde ir a partir de [location], ou `null` para ficar.
@visibleForTesting
String? redirectFor(AsyncValue<AuthState> auth, String location) {
  final target = switch (auth) {
    AsyncData(value: NeedsSetup()) => Routes.setup,
    AsyncData(value: SignedOut()) => Routes.login,
    AsyncData(value: SignedIn()) => switch (location) {
        Routes.startup || Routes.setup || Routes.login => Routes.home,
        _ => location,
      },
    _ => Routes.startup,
  };
  return target == location ? null : target;
}
