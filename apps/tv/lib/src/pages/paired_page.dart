import 'package:flutter/material.dart';

import '../realtime/device_connection.dart';
import '../widgets/tv_page.dart';

/// Estado vazio da TV pareada: ainda não há conteúdo para exibir. Mostra
/// também a situação da conexão com o servidor.
class PairedPage extends StatelessWidget {
  const PairedPage({super.key, required this.connection});

  final DeviceConnection connection;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final server = connection.credentials.server;

    return TvPage(
      title: 'TV pareada!',
      subtitle: 'Conectada a ${server.name ?? 'servidor'} · '
          '${server.hostPort}',
      children: [
        Text(
          'Aguardando conteúdo. Escolha no painel o que esta TV vai exibir.',
          style: textTheme.titleLarge,
        ),
        const SizedBox(height: 24),
        _StatusLine(connection: connection),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.connection});

  final DeviceConnection connection;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.headlineSmall;
    final text = switch (connection.status) {
      ConnectionStatus.online => 'Conectada',
      ConnectionStatus.connecting => 'Conectando…',
      ConnectionStatus.offline => _offlineText(connection.nextRetryIn),
      ConnectionStatus.replaced => 'Esta TV foi aberta em outro lugar.',
      ConnectionStatus.outdated => 'Atualize o app da TV.',
      ConnectionStatus.unauthorized => 'Esta TV foi removida do painel.',
    };
    return Row(
      children: [
        if (connection.status == ConnectionStatus.online) ...[
          const Icon(Icons.circle, color: Colors.green, size: 20),
          const SizedBox(width: 12),
        ],
        Flexible(child: Text(text, style: style)),
      ],
    );
  }

  static String _offlineText(Duration? left) {
    final seconds = left == null ? 0 : (left.inMilliseconds / 1000).ceil();
    return 'Sem conexão com o servidor. Tentando de novo em $seconds s.';
  }
}
