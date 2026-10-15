import 'package:flutter/material.dart';

import '../api/api_client.dart';

/// Pergunta um nome (1 a 64 caracteres) e chama [onSave]. O diálogo só fecha
/// se [onSave] terminar sem `ApiException`; devolve `true` nesse caso.
Future<bool> showNameDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required Future<void> Function(String name) onSave,
  String initial = '',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _NameDialog(
        title: title,
        confirmLabel: confirmLabel,
        initial: initial,
        onSave: onSave,
      ),
    ) ??
    false;

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.confirmLabel,
    required this.initial,
    required this.onSave,
  });

  final String title;
  final String confirmLabel;
  final String initial;
  final Future<void> Function(String name) onSave;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_name.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                maxLength: 64,
                decoration: const InputDecoration(labelText: 'Nome'),
                validator: (value) {
                  final length = (value ?? '').trim().length;
                  return length < 1 || length > 64
                      ? 'O nome deve ter de 1 a 64 caracteres.'
                      : null;
                },
                onFieldSubmitted: (_) => _save(),
              ),
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(widget.confirmLabel),
          ),
        ],
      );
}

/// Confirmação simples. Devolve `true` se o usuário confirmou.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ) ??
    false;
