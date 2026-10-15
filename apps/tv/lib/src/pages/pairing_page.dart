import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../device/device_info_source.dart';
import '../server/server_address.dart';
import '../server/tv_api.dart';
import '../theme.dart';
import '../widgets/pairing_keyboard.dart';
import '../widgets/tv_button.dart';

/// Digitação do código gerado no painel ("Adicionar TV").
///
/// Ao completar os 6 caracteres, envia sozinho. Também aceita um teclado
/// físico (útil no emulador).
class PairingPage extends StatefulWidget {
  const PairingPage({
    super.key,
    required this.server,
    required this.api,
    required this.deviceInfo,
    required this.onPaired,
    required this.onChangeServer,
  });

  final ServerAddress server;
  final TvApi api;
  final DeviceInfoSource deviceInfo;
  final ValueChanged<PairResponse> onPaired;
  final VoidCallback onChangeServer;

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  String _code = '';
  bool _busy = false;
  String? _error;

  void _type(String char) {
    if (_busy || _code.length >= pairingCodeLength) return;
    setState(() {
      _code += char;
      _error = null;
    });
    if (_code.length == pairingCodeLength) _submit();
  }

  void _backspace() {
    if (_busy || _code.isEmpty) return;
    setState(() => _code = _code.substring(0, _code.length - 1));
  }

  void _clear() {
    if (_busy) return;
    setState(() => _code = '');
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_code.length != pairingCodeLength) {
      setState(() => _error = 'Digite os $pairingCodeLength caracteres.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await widget.deviceInfo.read();
      final response = await widget.api.pair(
        widget.server,
        PairRequest(code: _code, deviceInfo: info),
      );
      if (mounted) widget.onPaired(response);
    } on TvApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        // Código errado ou vencido: começa de novo. Servidor fora do ar:
        // mantém o código para tentar outra vez.
        if (e.code != null) _code = '';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Teclado físico: letras e números válidos, Backspace e Delete.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete) {
      _clear();
      return KeyEventResult.handled;
    }
    final char = event.character?.toUpperCase();
    if (char != null &&
        char.length == 1 &&
        pairingCodeAlphabet.contains(char)) {
      _type(char);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final server = widget.server;

    return Scaffold(
      body: Focus(
        onKeyEvent: _onKey,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.tv, color: brandAccent, size: 32),
                            SizedBox(width: 12),
                            Text('Beyond TV', style: TextStyle(fontSize: 24)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text('Parear esta TV', style: textTheme.displaySmall),
                        const SizedBox(height: 8),
                        Text(
                          'No painel, clique em "Adicionar TV" e digite aqui o '
                          'código que aparecer.',
                          style: textTheme.titleMedium?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _CodeSlots(code: _code),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 48,
                          child: _busy
                              ? const Row(
                                  children: [
                                    SizedBox.square(
                                      dimension: 28,
                                      child: CircularProgressIndicator(),
                                    ),
                                    SizedBox(width: 16),
                                    Text(
                                      'Pareando…',
                                      style: TextStyle(fontSize: 22),
                                    ),
                                  ],
                                )
                              : Text(
                                  _error ?? '',
                                  style: TextStyle(
                                    color: colors.error,
                                    fontSize: 22,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Servidor: ${server.name ?? server.host} · '
                          '${server.hostPort}',
                          style: textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        TvButton(
                          icon: Icons.swap_horiz,
                          label: 'Trocar servidor',
                          onPressed: _busy ? null : widget.onChangeServer,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 48),
                PairingKeyboard(
                  enabled: !_busy,
                  onCharacter: _type,
                  onBackspace: _backspace,
                  onClear: _clear,
                  onSubmit: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Os 6 quadrados do código, preenchidos conforme a digitação.
class _CodeSlots extends StatelessWidget {
  const _CodeSlots({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Código digitado: $code',
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < pairingCodeLength; i++)
              Container(
                width: 64,
                height: 80,
                margin: const EdgeInsets.only(right: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: i == code.length ? brandAccent : Colors.white24,
                    width: i == code.length ? 3 : 2,
                  ),
                ),
                child: Text(
                  i < code.length ? code[i] : '',
                  style: const TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
