import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tv_button.dart';

/// Teclado na tela para digitar o código com o controle remoto.
///
/// Grade 6×6 só com os caracteres válidos do código, mais Apagar, Limpar e
/// OK. As setas do D-pad andam entre as teclas e o botão central aperta.
///
/// O próprio teclado move o foco pela grade: a busca padrão do Flutter olha
/// a tela inteira e, nas bordas, levava o foco para fora sem caminho de
/// volta. Só a seta para a esquerda na primeira coluna sai do teclado.
class PairingKeyboard extends StatefulWidget {
  const PairingKeyboard({
    super.key,
    required this.onCharacter,
    required this.onBackspace,
    required this.onClear,
    required this.onSubmit,
    this.enabled = true,
    this.exitLeft,
  });

  static const columns = 6;

  final ValueChanged<String> onCharacter;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSubmit;
  final bool enabled;

  /// Para onde a seta à esquerda leva a partir da primeira coluna.
  final FocusNode? exitLeft;

  @override
  State<PairingKeyboard> createState() => PairingKeyboardState();
}

class PairingKeyboardState extends State<PairingKeyboard> {
  static final _chars = pairingCodeAlphabet.split('');
  static final _keyCount = _chars.length + 3; // Apagar, Limpar e OK.

  static const _exit = -1;

  late final List<FocusNode> _nodes = List.generate(
    _keyCount,
    (i) => FocusNode(debugLabel: 'tecla $i'),
  );

  /// Última tecla com foco. Desabilitadas (pareando), as teclas perdem o
  /// foco; ao voltarem, o foco volta para esta, senão o controle não age.
  int _lastFocused = 0;

  @override
  void initState() {
    super.initState();
    for (final (index, node) in _nodes.indexed) {
      node.addListener(() {
        if (node.hasPrimaryFocus) _lastFocused = index;
      });
    }
  }

  @override
  void didUpdateWidget(PairingKeyboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Sem foco, ele fica no escopo da página. Se já está em outro
        // controle (ex.: Trocar servidor), não rouba.
        final current = FocusManager.instance.primaryFocus;
        if (current == null || current is FocusScopeNode) {
          focusLastKey();
        }
      });
    }
  }

  /// Põe o foco de volta na última tecla usada.
  void focusLastKey() => _nodes[_lastFocused].requestFocus();

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  /// Índice da tecla para onde a seta leva; [_exit] para sair pela
  /// esquerda e `null` se não é uma seta.
  static int? _target(int index, LogicalKeyboardKey key) {
    const columns = PairingKeyboard.columns;
    final row = index ~/ columns;
    final column = index % columns;
    final lastRow = (_keyCount - 1) ~/ columns;

    if (key == LogicalKeyboardKey.arrowLeft) {
      return column == 0 ? _exit : index - 1;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      final isRowEnd = column == columns - 1 || index == _keyCount - 1;
      return isRowEnd ? index : index + 1;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      return row == 0 ? index : index - columns;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (row == lastRow) return index;
      // A última fileira é incompleta: vai para a tecla mais próxima dela.
      final below = index + columns;
      return below < _keyCount ? below : _keyCount - 1;
    }
    return null;
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final index = _nodes.indexWhere((node) => node.hasPrimaryFocus);
    if (index < 0) return KeyEventResult.ignored;
    final target = _target(index, event.logicalKey);
    if (target == null) return KeyEventResult.ignored;
    if (target == _exit) {
      widget.exitLeft?.requestFocus();
    } else {
      _nodes[target].requestFocus();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final keys = <Widget>[
      for (final (index, char) in _chars.indexed)
        _Key(
          label: char,
          focusNode: _nodes[index],
          autofocus: index == 0,
          onPressed: enabled ? () => widget.onCharacter(char) : null,
        ),
      _Key(
        icon: Icons.backspace_outlined,
        tooltip: 'Apagar',
        focusNode: _nodes[_chars.length],
        onPressed: enabled ? widget.onBackspace : null,
      ),
      _Key(
        icon: Icons.clear_all,
        tooltip: 'Limpar',
        focusNode: _nodes[_chars.length + 1],
        onPressed: enabled ? widget.onClear : null,
      ),
      _Key(
        label: 'OK',
        focusNode: _nodes[_chars.length + 2],
        onPressed: enabled ? widget.onSubmit : null,
      ),
    ];

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: FocusTraversalGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var start = 0;
                start < keys.length;
                start += PairingKeyboard.columns)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final key
                      in keys.skip(start).take(PairingKeyboard.columns))
                    Padding(padding: const EdgeInsets.all(3), child: key),
                ],
              ),
          ],
        ),
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
    required this.focusNode,
    required this.onPressed,
  });

  final String? label;
  final IconData? icon;
  final String? tooltip;
  final bool autofocus;
  final FocusNode focusNode;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox.square(
      dimension: 56,
      child: OutlinedButton(
        autofocus: autofocus,
        focusNode: focusNode,
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
