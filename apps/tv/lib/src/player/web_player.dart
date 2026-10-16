import 'dart:async';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../remote/remote_input.dart';

/// Controle de um player aberto.
abstract interface class WebPlayerController {
  /// Recarrega o site atual.
  Future<void> reload();
}

/// Cria o player de [url]. [onCreated] entrega o controle assim que existe.
typedef WebPlayerBuilder = Widget Function(
  BuildContext context,
  String url,
  void Function(WebPlayerController controller) onCreated,
);

/// Player padrão: o [WebViewPlayer].
Widget defaultWebPlayer(
  BuildContext context,
  String url,
  void Function(WebPlayerController controller) onCreated,
) =>
    WebViewPlayer(url: url, onCreated: onCreated);

/// Site em tela cheia num WebView, com JavaScript, cookies persistentes,
/// sem acesso a arquivos e sem pontes JS.
class WebViewPlayer extends StatefulWidget {
  const WebViewPlayer({
    super.key,
    required this.url,
    required this.onCreated,
    this.retryAfter = const Duration(seconds: 30),
  });

  final String url;
  final void Function(WebPlayerController controller) onCreated;

  /// Espera antes de tentar de novo depois de um erro de carregamento.
  final Duration retryAfter;

  @override
  State<WebViewPlayer> createState() => _WebViewPlayerState();
}

class _WebViewPlayerState extends State<WebViewPlayer>
    implements WebPlayerController, RemoteInputTarget {
  late final WebViewController _controller;
  Timer? _retry;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigation,
          onPageStarted: (_) => _setFailed(false),
          onWebResourceError: _onError,
        ),
      );
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      unawaited(platform.setMediaPlaybackRequiresUserGesture(false));
      unawaited(platform.setAllowFileAccess(false));
    }
    unawaited(_load());
    widget.onCreated(this);
  }

  Future<void> _load() => _controller.loadRequest(Uri.parse(widget.url));

  NavigationDecision _onNavigation(NavigationRequest request) {
    final scheme = Uri.tryParse(request.url)?.scheme;
    return scheme == 'http' || scheme == 'https'
        ? NavigationDecision.navigate
        : NavigationDecision.prevent;
  }

  void _onError(WebResourceError error) {
    if (error.isForMainFrame == false) return;
    _setFailed(true);
    _retry?.cancel();
    _retry = Timer(widget.retryAfter, () {
      if (mounted) unawaited(_load());
    });
  }

  void _setFailed(bool value) {
    if (!mounted || _failed == value) return;
    setState(() => _failed = value);
  }

  @override
  Future<void> reload() {
    _retry?.cancel();
    return _load();
  }

  RemoteInputDriver? _input;

  @override
  Future<void> input(RemoteInput input) {
    final platform = _controller.platform;
    if (platform is! AndroidWebViewController) {
      throw const RemoteInputException('Controle remoto só no Android.');
    }
    final driver = _input ??= RemoteInputDriver(
      webViewId: platform.webViewIdentifier,
      runJavaScript: _controller.runJavaScriptReturningResult,
    );
    return driver.send(input);
  }

  @override
  void didUpdateWidget(WebViewPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _retry?.cancel();
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: _controller),
        if (_failed)
          const Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: Color(0xCC000000),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Text(
                  'Não foi possível carregar o site. Tentando de novo…',
                  style: TextStyle(fontSize: 24, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
