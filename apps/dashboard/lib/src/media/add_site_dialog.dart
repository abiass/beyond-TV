import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import 'media_controller.dart';

/// Pede o endereço (e um nome opcional) e salva o site na biblioteca.
Future<void> showAddSiteDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _AddSiteDialog(),
    );

class _AddSiteDialog extends ConsumerStatefulWidget {
  const _AddSiteDialog();

  @override
  ConsumerState<_AddSiteDialog> createState() => _AddSiteDialogState();
}

class _AddSiteDialogState extends ConsumerState<_AddSiteDialog> {
  final _formKey = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _name = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final name = _name.text.trim();
    try {
      await ref
          .read(mediaProvider.notifier)
          .addSite(_url.text.trim(), name: name.isEmpty ? null : name);
      if (mounted) Navigator.of(context).pop();
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
        title: const Text('Adicionar site'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _url,
                autofocus: true,
                maxLength: maxContentUrlLength,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Endereço do site',
                  hintText: 'https://example.local/painel',
                ),
                validator: (value) => isSafeContentUrl((value ?? '').trim())
                    ? null
                    : 'Use um link que comece com http:// ou https://.',
              ),
              TextFormField(
                controller: _name,
                maxLength: 64,
                decoration: const InputDecoration(
                  labelText: 'Nome (opcional)',
                  hintText: 'Usa o endereço se ficar vazio',
                ),
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
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Adicionar'),
          ),
        ],
      );
}
