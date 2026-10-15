import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../content/content_controller.dart';
import '../device/device_info_source.dart';
import '../media/media_cache.dart';
import '../realtime/device_connection.dart';
import '../theme.dart';
import '../widgets/tv_button.dart';
import 'app_log.dart';
import 'menu_trigger.dart';

/// Envolve a tela da TV pareada e abre o menu oculto com ⬆ ⬆ ⬇ ⬇ ou OK
/// segurado. Ouve o teclado sem tirar o foco de ninguém.
class HiddenMenuHost extends StatefulWidget {
  const HiddenMenuHost({
    super.key,
    required this.child,
    required this.content,
    required this.connection,
    this.log,
  });

  final Widget child;
  final ContentController content;
  final DeviceConnection connection;

  /// Log mostrado no menu; por padrão, o do app.
  final AppLog? log;

  @override
  State<HiddenMenuHost> createState() => _HiddenMenuHostState();
}

class _HiddenMenuHostState extends State<HiddenMenuHost> {
  late final MenuTrigger _trigger = MenuTrigger(onOpen: _open);
  bool _visible = false;

  /// Aberto com OK segurado: ignora o OK até ele ser solto, para o
  /// repeat da tecla não apertar um botão do menu.
  bool _awaitRelease = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _trigger.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (_visible) {
      if (event is KeyUpEvent && selectKeys.contains(event.logicalKey)) {
        _awaitRelease = false;
      }
    } else {
      _trigger.onKeyEvent(event);
    }
    return false;
  }

  void _open({required bool byHold}) {
    if (_visible || !mounted) return;
    setState(() {
      _visible = true;
      _awaitRelease = byHold;
    });
  }

  void _close() {
    if (!_visible) return;
    _trigger.reset();
    setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_visible,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_visible)
            Positioned.fill(
              child: HiddenMenu(
                content: widget.content,
                connection: widget.connection,
                log: widget.log ?? AppLog.instance,
                canActivate: () => !_awaitRelease,
                onClose: _close,
              ),
            ),
        ],
      ),
    );
  }
}

/// Overlay em tela cheia com informações da TV e as ações Recarregar,
/// Desparear e Fechar.
class HiddenMenu extends StatefulWidget {
  const HiddenMenu({
    super.key,
    required this.content,
    required this.connection,
    required this.log,
    required this.onClose,
    this.canActivate = _always,
  });

  final ContentController content;
  final DeviceConnection connection;
  final AppLog log;
  final VoidCallback onClose;

  /// `false` enquanto o OK que abriu o menu ainda está apertado.
  final bool Function() canActivate;

  static bool _always() => true;

  @override
  State<HiddenMenu> createState() => _HiddenMenuState();
}

class _HiddenMenuState extends State<HiddenMenu> {
  final _logScroll = ScrollController();
  CacheStats? _stats;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.content.addListener(_loadStats);
    unawaited(_loadStats());
  }

  @override
  void dispose() {
    widget.content.removeListener(_loadStats);
    _logScroll.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await widget.content.cacheStats();
      if (mounted) setState(() => _stats = stats);
    } on Object {
      // Sem leitura do cache: o menu mostra "indisponível".
    }
  }

  void _act(VoidCallback action) {
    if (_busy || !widget.canActivate()) return;
    action();
  }

  void _reload() => _act(() {
        unawaited(widget.content.reload());
        widget.onClose();
      });

  Future<void> _unpair() async {
    if (_busy || !widget.canActivate()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _ConfirmUnpairDialog(),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    // Sempre apaga o que é local, mesmo que o servidor não responda.
    await widget.content.unpairSelf();
    if (mounted) widget.onClose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.goBack ||
            event.logicalKey == LogicalKeyboardKey.escape)) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final credentials = widget.connection.credentials;
    final server = credentials.server;

    return Material(
      color: const Color(0xE60F172A),
      child: Focus(
        onKeyEvent: _onKey,
        child: FocusScope(
          autofocus: true,
          child: FocusTraversalGroup(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 64,
                  vertical: 32,
                ),
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    widget.connection,
                    widget.content,
                  ]),
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Menu da TV', style: textTheme.headlineMedium),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TvButton(
                              label: 'Recarregar',
                              icon: Icons.refresh,
                              autofocus: true,
                              onPressed: _reload,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TvButton(
                              label: 'Desparear',
                              icon: Icons.link_off,
                              onPressed: _unpair,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TvButton(
                              label: 'Fechar',
                              icon: Icons.close,
                              onPressed: () => _act(widget.onClose),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _InfoLine('Versão do app', appVersion),
                      _InfoLine('Id da TV', credentials.deviceId),
                      _InfoLine(
                        'Servidor',
                        '${server.name ?? 'servidor'} · ${server.hostPort}',
                      ),
                      _InfoLine('Conexão', _statusText(widget.connection)),
                      _InfoLine(
                        'Item exibido',
                        widget.content.currentItem ?? 'nenhum',
                      ),
                      _InfoLine(
                        'Revisão do manifesto',
                        widget.content.manifest.revision,
                      ),
                      _InfoLine('Cache', _cacheText(_stats)),
                      const SizedBox(height: 12),
                      Text('Log', style: textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Expanded(
                        child: _LogView(
                          log: widget.log,
                          controller: _logScroll,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _statusText(DeviceConnection connection) =>
      switch (connection.status) {
        ConnectionStatus.online => 'Conectada',
        ConnectionStatus.connecting => 'Conectando…',
        ConnectionStatus.offline => 'Sem conexão',
        ConnectionStatus.replaced => 'Aberta em outro lugar',
        ConnectionStatus.outdated => 'App desatualizado',
        ConnectionStatus.unauthorized => 'Removida do painel',
      };

  static String _cacheText(CacheStats? stats) {
    if (stats == null) return 'indisponível';
    final files = stats.files == 1 ? '1 arquivo' : '${stats.files} arquivos';
    return '$files · ${formatBytes(stats.bytes)}';
  }
}

/// Tamanho legível: `512 B`, `1,5 KB`, `3,2 MB`, `1,1 GB`.
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = unit == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1).replaceFirst('.', ',');
  return '$text ${units[unit]}';
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(color: Colors.white70),
            ),
            TextSpan(text: value),
          ],
        ),
        style: const TextStyle(fontSize: 18),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Últimas linhas do log; com foco, ⬆ e ⬇ rolam a lista.
class _LogView extends StatefulWidget {
  const _LogView({required this.log, required this.controller});

  final AppLog log;
  final ScrollController controller;

  @override
  State<_LogView> createState() => _LogViewState();
}

class _LogViewState extends State<_LogView> {
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    final down = event.logicalKey == LogicalKeyboardKey.arrowDown;
    if ((!up && !down) || !widget.controller.hasClients) {
      return KeyEventResult.ignored;
    }
    final position = widget.controller.position;
    final target = position.pixels + (down ? 80 : -80);
    final clamped =
        target.clamp(position.minScrollExtent, position.maxScrollExtent);
    // No limite da lista, deixa o foco seguir para outro botão.
    if (clamped == position.pixels) return KeyEventResult.ignored;
    widget.controller.jumpTo(clamped);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _onKey,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _focused ? brandAccent : Colors.white24,
            width: _focused ? 4 : 2,
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: ListenableBuilder(
          listenable: widget.log,
          builder: (context, _) {
            final lines = widget.log.lines;
            return ListView.builder(
              controller: widget.controller,
              itemCount: lines.length,
              itemBuilder: (context, i) => Text(
                lines[i],
                style: const TextStyle(
                  fontSize: 14,
                  fontFamily: 'monospace',
                  color: Colors.white70,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ConfirmUnpairDialog extends StatelessWidget {
  const _ConfirmUnpairDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Desparear esta TV?'),
      content: const Text('Ela volta para a tela de pareamento.'),
      actions: [
        TvButton(
          label: 'Cancelar',
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        TvButton(
          label: 'Desparear',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
