import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../theme.dart';
import 'pair_requests_controller.dart';

/// "Aguardando aprovação": TVs que abriram o app e pediram para entrar.
///
/// Some quando não há pedidos.
class PendingApprovals extends ConsumerWidget {
  const PendingApprovals({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(pairRequestsProvider).value ?? const [];
    if (requests.isEmpty) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;

    return Card(
      color: brandAccent.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: brandAccent.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Aguardando aprovação (${requests.length})',
                style: textTheme.titleMedium,
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                'Confira se o código é o mesmo que aparece na tela da TV.',
              ),
            ),
            for (final request in requests)
              _RequestTile(key: ValueKey(request.id), request: request),
          ],
        ),
      ),
    );
  }
}

class _RequestTile extends ConsumerStatefulWidget {
  const _RequestTile({super.key, required this.request});

  final PendingPairRequest request;

  @override
  ConsumerState<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends ConsumerState<_RequestTile> {
  bool _busy = false;

  Future<void> _run(Future<String> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final message = await action();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() => _run(() async {
        final device = await ref
            .read(pairRequestsProvider.notifier)
            .approve(widget.request.id);
        return '"${device.name}" foi pareada.';
      });

  Future<void> _reject() => _run(() async {
        await ref.read(pairRequestsProvider.notifier).reject(widget.request.id);
        return 'Pedido recusado.';
      });

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final info = request.deviceInfo;
    final details = [
      'IP ${request.ip}',
      if (info.androidVersion case final version?) 'Android $version',
    ].join(' · ');

    return ListTile(
      leading: const Icon(Icons.tv),
      title: Text(
        info.suggestedName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(details),
      trailing: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Semantics(
            label: 'Código ${request.confirmCode}',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: brandAccent),
              ),
              child: Text(
                request.confirmCode,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _reject,
            child: const Text('Recusar'),
          ),
          FilledButton(
            onPressed: _busy ? null : _approve,
            child: const Text('Aprovar'),
          ),
        ],
      ),
    );
  }
}
