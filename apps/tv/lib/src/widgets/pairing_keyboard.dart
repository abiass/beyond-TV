import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/material.dart';

import 'tv_button.dart';

/// Teclado na tela para digitar o código com o controle remoto.
///
/// Grade 6×6 só com os caracteres válidos do código, mais Apagar, Limpar e
/// OK. As setas do D-pad andam entre as teclas e o botão central aperta.
class PairingKeyboard extends StatelessWidget {
  const PairingKeyboard({
    super.key,
    required this.onCharacter,
    required this.onBackspace,
    required this.onClear,
    required this.onSubmit,
    this.enabled = true,
  });

  static const columns = 6;

  final ValueChanged<String> onCharacter;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSubmit;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final keys = <Widget>[
      for (final (index, char) in pairingCodeAlphabet.split('').indexed)
        _Key(
          label: char,
          autofocus: index == 0,
          onPressed: enabled ? () => onCharacter(char) : null,
        ),
      _Key(
        icon: Icons.backspace_outlined,
        tooltip: 'Apagar',
        onPressed: enabled ? onBackspace : null,
      ),
      _Key(
        icon: Icons.clear_all,
        tooltip: 'Limpar',
        onPressed: enabled ? onClear : null,
      ),
      _Key(label: 'OK', onPressed: enabled ? onSubmit : null),
    ];

    return FocusTraversalGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var start = 0; start < keys.length; start += columns)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final key in keys.skip(start).take(columns))
                  Padding(padding: const EdgeInsets.all(3), child: key),
              ],
            ),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    this.label,
    this.icon,
    this.tooltip,
    this.autofocus = false,
    required this.onPressed,
  });

  final String? label;
  final IconData? icon;
  final String? tooltip;
  final bool autofocus;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox.square(
      dimension: 56,
      child: OutlinedButton(
        autofocus: autofocus,
        onPressed: onPressed,
        style: tvFocusStyle().copyWith(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        ),
        child: icon != null
            ? Icon(icon, size: 28)
            : Text(
                label!,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
    return tooltip == null ? button : Semantics(label: tooltip, child: button);
  }
}
