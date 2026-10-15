import 'dart:async';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../auth/auth_controller.dart';
import '../realtime/admin_events.dart';
import '../router.dart';
import 'format_relative.dart';

/// Tempo que o painel espera o `device.screenshot` antes de desistir.
const screenshotWait = Duration(seconds: 15);

/// Card "Tela da TV": pede uma captura e mostra a última recebida.
class ScreenshotCard extends ConsumerStatefulWidget {
  const ScreenshotCard({required this.device, super.key});

  final DeviceSummary device;

  @override
  ConsumerState<ScreenshotCard> createState() => _ScreenshotCardState();
}

class _ScreenshotCardState extends ConsumerState<ScreenshotCard> {
  StreamSubscription<Envelope>? _sub;
  Timer? _timeout;
  DateTime? _capturedAt;
  bool _waiting = false;
  String? _message;

  String get _id => widget.device.id;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(adminEventsProvider).events.listen(_onEvent);
    unawaited(_loadLast());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timeout?.cancel();
    super.dispose();
  }

  Future<void> _loadLast() async {
    final at = await ref.read(apiClientProvider).getScreenshotInfo(_id);
    if (!mounted || at == null || _capturedAt != null) return;
    setState(() => _capturedAt = at);
  }

  void _onEvent(Envelope event) {
    if (event.type != MessageTypes.deviceScreenshot) return;
    final DeviceScreenshotEvent shot;
    try {
      shot = DeviceScreenshotEvent.fromJson(event.payload);
    } on ProtocolException {
      return;
    }
    if (shot.deviceId != _id) return;
    _timeout?.cancel();
    setState(() {
      _capturedAt = shot.capturedAt;
      _waiting = false;
      _message = null;
    });
  }

  Future<void> _capture() async {
    setState(() {
      _waiting = true;
      _message = null;
    });
    try {
      await ref.read(apiClientProvider).requestScreenshot(_id);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _waiting = false;
        _message = e.message;
      });
      return;
    }
    if (!mounted) return;
    _timeout?.cancel();
    _timeout = Timer(screenshotWait, () {
      if (!mounted || !_waiting) return;
      setState(() {
        _waiting = false;
        _message = 'A TV não respondeu.';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // Mantém o canal ao vivo aberto enquanto o card existe.
    ref.watch(adminEventsProvider);
    final online = widget.device.online;
    final at = _capturedAt;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tela da TV', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (at != null) ...[
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ColoredBox(
                  color: Colors.black,
                  child: Image.network(
                    ref
                        .read(apiClientProvider)
                        .screenshotUrl(_id, capturedAt: at)
                        .toString(),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Text(
                        'Não foi possível carregar a imagem.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Capturada ${formatRelative(at, clock.now())}',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                'A captura fica só na memória do servidor.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
            ],
            if (_waiting) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 4),
              const Text('Aguardando a TV…'),
              const SizedBox(height: 8),
            ],
            if (_message case final message?) ...[
              Text(
                message,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Tooltip(
                  message: online
                      ? 'Tira uma foto da tela da TV'
                      : 'A TV está offline',
                  child: OutlinedButton.icon(
                    onPressed: online && !_waiting ? _capture : null,
                    icon: const Icon(Icons.screenshot_monitor),
                    label: const Text('Capturar tela'),
                  ),
                ),
                Tooltip(
                  message: online
                      ? 'Vê a tela ao vivo e usa o site da TV pelo PC '
                          '(login, cliques, digitação)'
                      : 'A TV está offline',
                  child: FilledButton.icon(
                    onPressed: online
                        ? () => context.go(Routes.liveControl(_id))
                        : null,
                    icon: const Icon(Icons.mouse),
                    label: const Text('Controlar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
