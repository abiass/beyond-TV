import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import 'devices_controller.dart';

/// Pergunta o novo nome da TV e o salva.
Future<void> showRenameDeviceDialog(
  BuildContext context,
  DeviceSummary device,
) =>
    showDialog<void>(
      context: context,
      builder: (_) => RenameDeviceDialog(device: device),
    );

class RenameDeviceDialog extends ConsumerStatefulWidget {
  const RenameDeviceDialog({required this.device, super.key});

  final DeviceSummary device;

  @override
  ConsumerState<RenameDeviceDialog> createState() => _RenameDeviceDialogState();
}

class _RenameDeviceDialogState extends ConsumerState<RenameDeviceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.device.name);
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
      await ref
          .read(devicesProvider.notifier)
          .rename(widget.device.id, _name.text.trim());
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
        title: const Text('Renomear TV'),
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
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Salvar'),
          ),
        ],
      );
}
