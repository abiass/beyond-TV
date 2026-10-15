import 'package:flutter/material.dart';

import '../server/server_address.dart';
import '../server/tv_api.dart';
import '../widgets/tv_button.dart';
import '../widgets/tv_page.dart';

/// Entrada manual do IP do servidor, para quando a descoberta não funciona.
///
/// Confere se o endereço responde como um servidor Beyond TV antes de
/// devolvê-lo com `Navigator.pop`.
class ManualAddressPage extends StatefulWidget {
  const ManualAddressPage({super.key, required this.api});

  final TvApi api;

  @override
  State<ManualAddressPage> createState() => _ManualAddressPageState();
}

class _ManualAddressPageState extends State<ManualAddressPage> {
  final _controller = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final address = ServerAddress.parse(_controller.text);
    if (address == null) {
      setState(() => _error = _invalidAddress);
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      await widget.api.checkServer(address);
      if (mounted) Navigator.of(context).pop(address);
    } on TvApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  static const _invalidAddress = 'Endereço inválido. Use o formato '
      '192.168.0.10 ou 192.168.0.10:$defaultServerPort.';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return TvPage(
      title: 'Digitar IP do servidor',
      subtitle: 'É o IP do PC onde o servidor roda (no Windows, veja com '
          'o comando ipconfig). Ex.: 192.168.0.10 ou '
          '192.168.0.10:$defaultServerPort',
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          enabled: !_checking,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          style: const TextStyle(fontSize: 32),
          decoration: const InputDecoration(
            labelText: 'IP do servidor',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _connect(),
        ),
        if (_error case final error?) ...[
          const SizedBox(height: 16),
          Text(error, style: TextStyle(color: colors.error, fontSize: 20)),
        ],
        const SizedBox(height: 24),
        Wrap(
          spacing: 16,
          children: [
            TvButton(
              icon: Icons.link,
              label: _checking ? 'Conectando…' : 'Conectar',
              onPressed: _checking ? null : _connect,
            ),
            TvButton(
              icon: Icons.arrow_back,
              label: 'Voltar',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }
}
