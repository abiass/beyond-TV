import 'package:flutter/material.dart';

import '../server/discovery.dart';
import '../server/server_address.dart';
import '../server/tv_api.dart';
import '../widgets/tv_button.dart';
import '../widgets/tv_page.dart';
import 'manual_address_page.dart';

/// Lista os servidores encontrados na rede e oferece "Digitar IP".
class ServerSelectPage extends StatefulWidget {
  const ServerSelectPage({
    super.key,
    required this.discovery,
    required this.api,
    required this.onSelected,
  });

  final ServerDiscovery discovery;
  final TvApi api;
  final ValueChanged<ServerAddress> onSelected;

  @override
  State<ServerSelectPage> createState() => _ServerSelectPageState();
}

class _ServerSelectPageState extends State<ServerSelectPage> {
  List<ServerAddress>? _servers;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() {
      _servers = null;
      _failed = false;
    });
    try {
      final servers = await widget.discovery.discover();
      if (mounted) setState(() => _servers = servers);
    } on Exception {
      if (mounted) {
        setState(() {
          _servers = const [];
          _failed = true;
        });
      }
    }
  }

  Future<void> _typeAddress() async {
    final address = await Navigator.of(context).push<ServerAddress>(
      MaterialPageRoute(builder: (_) => ManualAddressPage(api: widget.api)),
    );
    if (address != null) widget.onSelected(address);
  }

  @override
  Widget build(BuildContext context) {
    final servers = _servers;
    final textTheme = Theme.of(context).textTheme;

    return TvPage(
      title: 'Escolha o servidor',
      subtitle:
          'O servidor Beyond TV precisa estar ligado no PC da mesma rede.',
      children: [
        if (servers == null)
          const Row(
            children: [
              SizedBox.square(
                dimension: 32,
                child: CircularProgressIndicator(),
              ),
              SizedBox(width: 16),
              Text('Procurando servidores na rede…'),
            ],
          )
        else ...[
          if (servers.isEmpty)
            Text(
              _failed
                  ? 'Não foi possível procurar na rede. Digite o IP do PC.'
                  : 'Nenhum servidor encontrado. Confira se ele está ligado '
                      'e na mesma rede, ou digite o IP do PC.',
              style: textTheme.titleMedium,
            ),
          for (final (index, server) in servers.indexed) ...[
            TvButton(
              autofocus: index == 0,
              icon: Icons.computer,
              label: server.name ?? server.host,
              subtitle: server.hostPort,
              onPressed: () => widget.onSelected(server),
            ),
            const SizedBox(height: 12),
          ],
        ],
        const SizedBox(height: 24),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            TvButton(
              autofocus: servers != null && servers.isEmpty,
              icon: Icons.keyboard,
              label: 'Digitar IP',
              onPressed: _typeAddress,
            ),
            TvButton(
              icon: Icons.refresh,
              label: 'Procurar de novo',
              onPressed: servers == null ? null : _search,
            ),
          ],
        ),
      ],
    );
  }
}
