import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'device/credentials.dart';
import 'device/device_info_source.dart';
import 'content/content_controller.dart';
import 'content/manifest_store.dart';
import 'media/media_cache.dart';
import 'pages/player_page.dart';
import 'player/video_player_view.dart';
import 'player/web_player.dart';
import 'pages/pairing_page.dart';
import 'pages/server_select_page.dart';
import 'realtime/backoff.dart';
import 'realtime/device_connection.dart';
import 'realtime/socket_connector.dart';
import 'server/discovery.dart';
import 'server/server_address.dart';
import 'server/tv_api.dart';
import 'theme.dart';
import 'remote/app_log.dart';
import 'remote/screen_capturer.dart';
import 'system/system_settings.dart';

class TvApp extends StatelessWidget {
  TvApp({
    super.key,
    ServerDiscovery? discovery,
    TvApi? api,
    DeviceInfoSource? deviceInfo,
    CredentialStore? credentials,
    SocketConnector? connector,
    this.backoffFactory,
    ManifestStore? manifestStore,
    WebPlayerBuilder? webPlayer,
    this.videoSurface = defaultVideoSurface,
    this.mediaRoot = _defaultMediaRoot,
    this.mediaClient,
    this.now,
    ScreenCapturer? screenCapturer,
    this.systemSettings = const PlatformSystemSettings(),
  })  : _screenCapturer = screenCapturer,
        discovery = discovery ?? const UdpServerDiscovery(),
        api = api ?? TvApi(),
        deviceInfo = deviceInfo ?? const PlatformDeviceInfoSource(),
        credentials = credentials ?? const SecureCredentialStore(),
        connector = connector ?? ioConnector,
        manifestStore = manifestStore ?? FileManifestStore(),
        webPlayer = webPlayer ?? defaultWebPlayer;

  final ScreenCapturer? _screenCapturer;

  /// Raiz da árvore do app, para a captura de tela de reserva.
  final GlobalKey _boundaryKey = GlobalKey();

  late final ScreenCapturer screenCapturer =
      _screenCapturer ?? PlatformScreenCapturer(boundaryKey: _boundaryKey);

  /// Opções de sistema (abrir ao ligar, quiosque); os testes injetam um falso.
  final SystemSettings systemSettings;

  final ServerDiscovery discovery;
  final TvApi api;
  final DeviceInfoSource deviceInfo;
  final CredentialStore credentials;
  final SocketConnector connector;
  final ManifestStore manifestStore;
  final WebPlayerBuilder webPlayer;
  final VideoSurfaceFactory videoSurface;

  /// Pasta do cache de mídia; os testes usam uma pasta temporária.
  final Future<Directory> Function() mediaRoot;

  /// Cliente HTTP do cache; os testes injetam um falso.
  final http.Client Function()? mediaClient;

  /// Relógio da agenda; os testes injetam um falso.
  final DateTime Function()? now;

  static Future<Directory> _defaultMediaRoot() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/media');
  }

  /// Abre o cache de mídia; sem pasta, a TV só exibe sites.
  Future<MediaCache?> _openCache() async {
    try {
      final root = await mediaRoot();
      return MediaCache(
        root: root,
        client: mediaClient?.call() ?? http.Client(),
      );
    } on Object catch (e) {
      appLog('Cache de mídia indisponível: $e');
      return null;
    }
  }

  /// Cria o backoff de cada conexão; os testes usam esperas curtas.
  final Backoff Function()? backoffFactory;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beyond TV',
      debugShowCheckedModeBanner: false,
      theme: buildTvTheme(),
      builder: (context, child) => SystemSettingsScope(
        settings: systemSettings,
        child: RepaintBoundary(
          key: _boundaryKey,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: _StartupPage(app: this),
    );
  }

  Widget _serverSelect() => Builder(
        builder: (context) => ServerSelectPage(
          discovery: discovery,
          api: api,
          onSelected: (server) => _openPairing(context, server),
        ),
      );

  Widget _paired(Credentials saved, MediaCache? cache) {
    late final ContentController content;
    final connection = DeviceConnection(
      credentials: saved,
      deviceInfo: deviceInfo,
      store: credentials,
      discovery: discovery,
      connector: connector,
      backoff: backoffFactory?.call(),
      currentItem: () => content.currentItem,
    );
    content = ContentController(
      store: manifestStore,
      connection: connection,
      credentials: credentials,
      cache: cache,
      api: api,
      screenCapturer: screenCapturer,
      now: now,
    );
    return PlayerPage(
      content: content,
      connection: connection,
      webPlayer: webPlayer,
      videoSurface: videoSurface,
      onUnauthorized: _backToPairing,
    );
  }

  /// A TV foi removida no painel: volta à seleção de servidor.
  void _backToPairing(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => _serverSelect()),
      (_) => false,
    );
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Esta TV foi removida do painel. Pareie de novo.',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }

  void _openPairing(BuildContext context, ServerAddress server) {
    final navigator = Navigator.of(context);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => PairingPage(
          server: server,
          api: api,
          deviceInfo: deviceInfo,
          onChangeServer: navigator.pop,
          onPaired: (pair) async {
            final saved = Credentials.fromPairing(server, pair);
            await credentials.save(saved);
            final cache = await _openCache();
            navigator.pushAndRemoveUntil(
              MaterialPageRoute<void>(
                builder: (_) => _paired(saved, cache),
              ),
              (_) => false,
            );
          },
        ),
      ),
    );
  }
}

/// Splash: decide entre o pareamento e a TV já pareada.
class _StartupPage extends StatefulWidget {
  const _StartupPage({required this.app});

  final TvApp app;

  @override
  State<_StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<_StartupPage> {
  late final Future<Credentials?> _saved = _load();

  /// Guardada para um rebuild não abrir outra conexão.
  Widget? _page;

  MediaCache? _cache;

  Future<Credentials?> _load() async {
    try {
      final saved = await widget.app.credentials.load();
      if (saved != null) _cache = await widget.app._openCache();
      return saved;
    } on Exception {
      // Armazenamento indisponível: melhor parear de novo do que travar.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _saved,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: Icon(Icons.tv, size: 96, color: brandAccent),
            ),
          );
        }
        return switch (snapshot.data) {
          final saved? => _page ??= widget.app._paired(saved, _cache),
          null => widget.app._serverSelect(),
        };
      },
    );
  }
}
