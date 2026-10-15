import 'dart:async';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../auth/auth_controller.dart';

/// Abre o fluxo "Adicionar TV".
Future<void> showAddTvDialog(BuildContext context) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AddTvDialog(),
    );

/// Gera um código, mostra com contagem regressiva e acompanha até a TV
/// parear (ou o código vencer).
class AddTvDialog extends ConsumerStatefulWidget {
  const AddTvDialog({super.key});

  /// Intervalo da consulta ao servidor enquanto espera a TV.
  static const pollInterval = Duration(seconds: 2);

  @override
  ConsumerState<AddTvDialog> createState() => _AddTvDialogState();
}

sealed class _Step {
  const _Step();
}

final class _Loading extends _Step {
  const _Loading();
}

final class _Waiting extends _Step {
  const _Waiting(this.code, this.deadline);

  final String code;

  /// Fim da validade no relógio deste navegador.
  final DateTime deadline;
}

final class _Paired extends _Step {
  const _Paired(this.deviceName);

  final String? deviceName;
}

final class _Expired extends _Step {
  const _Expired();
}

final class _Failed extends _Step {
  const _Failed(this.message);

  final String message;
}

class _AddTvDialogState extends ConsumerState<AddTvDialog> {
  _Step _step = const _Loading();
  Timer? _ticker;
  Timer? _poller;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    _stopTimers();
    super.dispose();
  }

  void _stopTimers() {
    _ticker?.cancel();
    _poller?.cancel();
  }

  Future<void> _generate() async {
    _stopTimers();
    setState(() => _step = const _Loading());
    try {
      final code = await ref.read(apiClientProvider).createPairingCode();
      if (!mounted) return;
      // A contagem usa o relógio do navegador, que pode não bater com o do
      // servidor. A situação real vem da consulta periódica.
      final deadline = clock.now().add(pairingCodeTtl);
      setState(() => _step = _Waiting(code.code, deadline));
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      _poller = Timer.periodic(AddTvDialog.pollInterval, (_) => _poll());
    } on ApiException catch (e) {
      _fail(e);
    }
  }

  void _tick() {
    if (_step case _Waiting(:final deadline)
        when !clock.now().isBefore(deadline)) {
      _finish(const _Expired());
    } else {
      setState(() {});
    }
  }

  Future<void> _poll() async {
    final step = _step;
    if (step is! _Waiting || _polling) return;
    _polling = true;
    try {
      final status = await ref.read(apiClientProvider).pairingStatus(step.code);
      if (!mounted || _step != step) return;
      switch (status.state) {
        case PairingState.paired:
          _finish(_Paired(status.deviceName));
        case PairingState.expired:
          _finish(const _Expired());
        case PairingState.pending:
          break;
      }
    } on ApiException catch (e) {
      // Falha passageira de rede: tenta de novo no próximo ciclo.
      if (e.status != null) _fail(e);
    } finally {
      _polling = false;
    }
  }

  void _finish(_Step step) {
    _stopTimers();
    if (mounted) setState(() => _step = step);
  }

  void _fail(ApiException error) {
    if (!mounted) return;
    if (error.status == 401) {
      Navigator.of(context).pop();
      ref.read(authProvider.notifier).sessionExpired();
      return;
    }
    _finish(_Failed(error.message));
  }

  @override
  Widget build(BuildContext context) {
    final close = TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: Text(_step is _Paired ? 'Fechar' : 'Cancelar'),
    );

    return AlertDialog(
      title: const Text('Adicionar TV'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 360, maxWidth: 420),
        child: switch (_step) {
          _Loading() => const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            ),
          _Waiting(:final code, :final deadline) =>
            _WaitingContent(code: code, deadline: deadline),
          _Paired(:final deviceName) => _ResultContent(
              icon: Icons.check_circle,
              iconColor: Colors.green,
              title: 'TV pareada!',
              message: deviceName == null
                  ? 'A TV já aparece no painel.'
                  : '"$deviceName" já aparece no painel.',
            ),
          _Expired() => const _ResultContent(
              icon: Icons.timer_off,
              title: 'Código expirado',
              message: 'Gere um novo código e digite na TV.',
            ),
          _Failed(:final message) => _ResultContent(
              icon: Icons.error_outline,
              title: 'Não foi possível gerar o código',
              message: message,
            ),
        },
      ),
      actions: [
        if (_step case _Expired() || _Failed())
          FilledButton(
            onPressed: _generate,
            child: const Text('Gerar novo código'),
          ),
        close,
      ],
    );
  }
}

class _WaitingContent extends StatelessWidget {
  const _WaitingContent({required this.code, required this.deadline});

  final String code;
  final DateTime deadline;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final remaining = deadline.difference(clock.now());
    final seconds = remaining.isNegative ? 0 : remaining.inSeconds + 1;
    final countdown = '${seconds ~/ 60}:${'${seconds % 60}'.padLeft(2, '0')}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Abra o app Beyond TV na TV, escolha este servidor e digite o '
          'código:',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SelectableText(
          '${code.substring(0, 3)} ${code.substring(3)}',
          style: textTheme.displayMedium?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 8,
          ),
          semanticsLabel: code.split('').join(' '),
        ),
        const SizedBox(height: 16),
        Text('Expira em $countdown', style: textTheme.titleMedium),
        const SizedBox(height: 16),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Aguardando a TV…'),
          ],
        ),
      ],
    );
  }
}

class _ResultContent extends StatelessWidget {
  const _ResultContent({
    required this.icon,
    required this.title,
    required this.message,
    this.iconColor,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 56, color: iconColor),
        const SizedBox(height: 12),
        Text(title, style: textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
      ],
    );
  }
}
