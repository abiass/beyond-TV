import 'dart:async';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../auth/auth_controller.dart';
import '../realtime/admin_events.dart';
import '../router.dart';
import 'devices_controller.dart';

/// Espera por um quadro antes de pedir outro (a TV pode ter falhado a
/// captura sem avisar).
const liveFrameWait = Duration(seconds: 2);

/// Pausa entre um quadro recebido e o pedido do próximo: só o bastante
/// para a tela ser redesenhada.
const liveFrameGap = Duration(milliseconds: 16);

/// Junta as letras digitadas antes de enviar, para não mandar uma
/// requisição por tecla.
const liveTypingBatch = Duration(milliseconds: 120);

/// Controle ao vivo: a tela da TV atualizando sozinha, com clique, teclado
/// e roda do mouse levados para o site aberto na TV.
class LiveControlPage extends ConsumerStatefulWidget {
  const LiveControlPage({required this.id, super.key});

  final String id;

  @override
  ConsumerState<LiveControlPage> createState() => _LiveControlPageState();
}

class _LiveControlPageState extends ConsumerState<LiveControlPage> {
  final _focus = FocusNode(debugLabel: 'controle ao vivo');
  StreamSubscription<Envelope>? _sub;
  Timer? _frameTimer;
  Timer? _typingTimer;
  Timer? _scrollTimer;
  Timer? _noticeTimer;
  DateTime? _capturedAt;
  String? _status = 'Conectando à TV…';
  String? _notice;
  bool _disposed = false;
  final _typed = StringBuffer();
  double _scrollDy = 0;
  Offset _scrollAt = const Offset(0.5, 0.5);
  Future<void> _queue = Future.value();

  String get _id => widget.id;
  ApiClient get _api => ref.read(apiClientProvider);

  @override
  void initState() {
    super.initState();
    _sub = ref.read(adminEventsProvider).events.listen(_onEvent);
    unawaited(_start());
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _frameTimer?.cancel();
    _typingTimer?.cancel();
    _scrollTimer?.cancel();
    _noticeTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      await _api.startLiveControl(_id);
    } on ApiException catch (e) {
      if (!_disposed) setState(() => _status = e.message);
      _retryLater(const Duration(seconds: 3), _start);
      return;
    }
    _requestFrame();
  }

  void _retryLater(Duration delay, Future<void> Function() action) {
    _frameTimer?.cancel();
    _frameTimer = Timer(delay, () {
      if (!_disposed) unawaited(action());
    });
  }

  void _requestFrame() {
    if (_disposed) return;
    _frameTimer?.cancel();
    unawaited(() async {
      try {
        await _api.requestLiveFrame(_id);
      } on ApiException catch (e) {
        if (_disposed) return;
        if (e.status == 429) {
          // Pedido cedo demais: tenta logo em seguida.
          _retryLater(liveFrameGap, () async => _requestFrame());
          return;
        }
        setState(() => _status = e.message);
        _retryLater(const Duration(seconds: 2), () async => _requestFrame());
        return;
      }
      // Se o quadro não chegar, pede de novo.
      _retryLater(liveFrameWait, () async => _requestFrame());
    }());
  }

  void _onEvent(Envelope event) {
    final deviceId = event.payload['deviceId'];
    if (deviceId != _id) return;
    switch (event.type) {
      case MessageTypes.deviceScreenshot:
        final DeviceScreenshotEvent shot;
        try {
          shot = DeviceScreenshotEvent.fromJson(event.payload);
        } on ProtocolException {
          return;
        }
        setState(() {
          _capturedAt = shot.capturedAt;
          _status = null;
        });
        _retryLater(liveFrameGap, () async => _requestFrame());
      case MessageTypes.deviceInputError:
        _showNotice('${event.payload['message'] ?? 'A TV não executou.'}');
    }
  }

  void _showNotice(String message) {
    if (_disposed) return;
    _noticeTimer?.cancel();
    setState(() => _notice = message);
    _noticeTimer = Timer(const Duration(seconds: 5), () {
      if (!_disposed) setState(() => _notice = null);
    });
  }

  /// Envia em ordem: cada entrada espera a anterior.
  void _send(RemoteInput input) {
    _queue = _queue.then((_) async {
      try {
        await _api.sendRemoteInput(_id, input);
      } on ApiException catch (e) {
        _showNotice(e.message);
      }
    });
  }

  void _flushTyped() {
    _typingTimer?.cancel();
    if (_typed.isEmpty) return;
    final text = _typed.toString();
    _typed.clear();
    for (var i = 0; i < text.length; i += maxRemoteTextLength) {
      final end = i + maxRemoteTextLength;
      _send(RemoteInput.text(text.substring(i, end.clamp(0, text.length))));
    }
  }

  void _type(String text) {
    _typed.write(text);
    _typingTimer?.cancel();
    _typingTimer = Timer(liveTypingBatch, _flushTyped);
  }

  void _key(String key) {
    _flushTyped();
    _send(RemoteInput.key(key));
  }

  static final _keys = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.enter: RemoteKeys.enter,
    LogicalKeyboardKey.numpadEnter: RemoteKeys.enter,
    LogicalKeyboardKey.tab: RemoteKeys.tab,
    LogicalKeyboardKey.backspace: RemoteKeys.backspace,
    LogicalKeyboardKey.delete: RemoteKeys.delete,
    LogicalKeyboardKey.escape: RemoteKeys.escape,
    LogicalKeyboardKey.arrowUp: RemoteKeys.up,
    LogicalKeyboardKey.arrowDown: RemoteKeys.down,
    LogicalKeyboardKey.arrowLeft: RemoteKeys.left,
    LogicalKeyboardKey.arrowRight: RemoteKeys.right,
    LogicalKeyboardKey.pageUp: RemoteKeys.pageUp,
    LogicalKeyboardKey.pageDown: RemoteKeys.pageDown,
    LogicalKeyboardKey.home: RemoteKeys.home,
    LogicalKeyboardKey.end: RemoteKeys.end,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final shortcut = keyboard.isControlPressed || keyboard.isMetaPressed;
    if (shortcut && event.logicalKey == LogicalKeyboardKey.keyV) {
      unawaited(_paste());
      return KeyEventResult.handled;
    }
    final key = _keys[event.logicalKey];
    if (key != null) {
      _key(
        key == RemoteKeys.tab && keyboard.isShiftPressed
            ? RemoteKeys.shiftTab
            : key,
      );
      return KeyEventResult.handled;
    }
    final char = event.character;
    if (!shortcut && char != null && char.isNotEmpty && !_isControl(char)) {
      _type(char);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static bool _isControl(String char) =>
      char.runes.every((r) => r < 0x20 || r == 0x7f);

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) _type(text);
  }

  void _tap(Offset fraction) {
    _focus.requestFocus();
    _flushTyped();
    _send(RemoteInput.tap(fraction.dx, fraction.dy));
  }

  void _scroll(Offset fraction, double screens) {
    _scrollAt = fraction;
    _scrollDy += screens;
    _scrollTimer ??= Timer(const Duration(milliseconds: 100), () {
      _scrollTimer = null;
      final dy = _scrollDy.clamp(-5.0, 5.0);
      _scrollDy = 0;
      if (dy.abs() < 0.01) return;
      _send(RemoteInput.scroll(dy, x: _scrollAt.dx, y: _scrollAt.dy));
    });
  }

  @override
  Widget build(BuildContext context) {
    // Mantém o canal ao vivo aberto enquanto a página existe.
    ref.watch(adminEventsProvider);
    final device =
        ref.watch(devicesProvider).value?.where((d) => d.id == _id).firstOrNull;
    final capturedAt = _capturedAt;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(Routes.device(_id)),
        ),
        title: Text('Controlar ${device?.name ?? 'TV'}'),
        actions: [
          IconButton(
            tooltip: 'Página anterior do site',
            icon: const Icon(Icons.undo),
            onPressed: () => _key(RemoteKeys.back),
          ),
          IconButton(
            tooltip: 'Recarregar o site',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              try {
                await _api.sendCommand(_id, DeviceCommands.reload);
              } on ApiException catch (e) {
                _showNotice(e.message);
              }
            },
          ),
          IconButton(
            tooltip: 'Rolar para cima',
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: () => _send(const RemoteInput.scroll(-0.5)),
          ),
          IconButton(
            tooltip: 'Rolar para baixo',
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () => _send(const RemoteInput.scroll(0.5)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: LayoutBuilder(
                      builder: (context, box) {
                        Offset fraction(Offset local) => Offset(
                              (local.dx / box.maxWidth).clamp(0.0, 1.0),
                              (local.dy / box.maxHeight).clamp(0.0, 1.0),
                            );
                        return Listener(
                          onPointerSignal: (signal) {
                            if (signal is PointerScrollEvent) {
                              _scroll(
                                fraction(signal.localPosition),
                                signal.scrollDelta.dy / box.maxHeight,
                              );
                            }
                          },
                          child: GestureDetector(
                            onTapUp: (details) =>
                                _tap(fraction(details.localPosition)),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.precise,
                              child: ColoredBox(
                                color: Colors.black,
                                child: capturedAt == null
                                    ? const Center(
                                        child: CircularProgressIndicator(),
                                      )
                                    : Image.network(
                                        _api
                                            .screenshotUrl(
                                              _id,
                                              capturedAt: capturedAt,
                                            )
                                            .toString(),
                                        key: const ValueKey('tela-da-tv'),
                                        fit: BoxFit.fill,
                                        // Mantém o quadro anterior enquanto
                                        // o novo carrega, sem piscar.
                                        gaplessPlayback: true,
                                        errorBuilder: (context, error, _) =>
                                            const SizedBox.shrink(),
                                      ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  if (_notice != null || _status != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _notice ?? _status!,
                        style: TextStyle(
                          color: _notice != null
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  Text(
                    'Clique na imagem para tocar na TV e digite com o teclado '
                    'do PC (Ctrl+V cola). A roda do mouse rola a página. '
                    'Só funciona quando a TV está exibindo um site.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
