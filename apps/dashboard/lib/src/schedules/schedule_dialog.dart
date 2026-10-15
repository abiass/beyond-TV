import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/playlists.dart';
import '../api/schedules.dart';
import 'schedule_format.dart';

/// Formulário de criar ou editar um agendamento do alvo ([deviceId] ou
/// [groupId]). [onSave] grava na API; o diálogo só fecha se terminar sem
/// `ApiException`. Devolve `true` se salvou.
Future<bool> showScheduleDialog(
  BuildContext context, {
  required List<PlaylistSummary> playlists,
  required Future<void> Function(Schedule schedule) onSave,
  String? deviceId,
  int? groupId,
  Schedule? existing,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _ScheduleDialog(
        playlists: playlists,
        onSave: onSave,
        deviceId: deviceId,
        groupId: groupId,
        existing: existing,
      ),
    ) ??
    false;

const _weekdays = {1, 2, 3, 4, 5};

class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog({
    required this.playlists,
    required this.onSave,
    required this.deviceId,
    required this.groupId,
    required this.existing,
  });

  final List<PlaylistSummary> playlists;
  final Future<void> Function(Schedule schedule) onSave;
  final String? deviceId;
  final int? groupId;
  final Schedule? existing;

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _start = TextEditingController(
    text: formatClockTime(widget.existing?.startMinute ?? 8 * 60),
  );
  late final _end = TextEditingController(
    text: formatClockTime(widget.existing?.endMinute ?? 18 * 60),
  );
  late final _priority = TextEditingController(
    text: '${widget.existing?.priority ?? 0}',
  );
  late final Set<int> _days = {...?widget.existing?.days};
  late String? _playlistId =
      widget.playlists.any((p) => p.id == widget.existing?.playlistId)
          ? widget.existing?.playlistId
          : null;
  bool _daysMissing = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _start.dispose();
    _end.dispose();
    _priority.dispose();
    super.dispose();
  }

  static String? _validateTime(String? value) =>
      parseClockTime((value ?? '').trim()) == null
          ? 'Use HH:MM, de 00:00 a 23:59.'
          : null;

  Future<void> _pickTime(TextEditingController controller) async {
    final current = parseClockTime(controller.text.trim()) ?? 0;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) return;
    setState(() {
      controller.text = formatClockTime(picked.hour * 60 + picked.minute);
    });
  }

  /// Aviso sobre a faixa digitada, se ela vira a noite ou cobre 24 h.
  String? get _notice {
    final start = parseClockTime(_start.text.trim());
    final end = parseClockTime(_end.text.trim());
    if (start == null || end == null) return null;
    if (end == start) return 'Cobre 24 horas.';
    if (end < start) return 'Termina no dia seguinte.';
    return null;
  }

  Future<void> _save() async {
    final valid = _formKey.currentState!.validate();
    setState(() => _daysMissing = _days.isEmpty);
    if (!valid || _days.isEmpty) return;

    final schedule = Schedule(
      id: widget.existing?.id ?? '',
      name: _name.text.trim(),
      playlistId: _playlistId!,
      deviceId: widget.deviceId,
      groupId: widget.groupId,
      days: {..._days},
      startMinute: parseClockTime(_start.text.trim())!,
      endMinute: parseClockTime(_end.text.trim())!,
      priority: int.parse(_priority.text.trim()),
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(schedule);
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

  Widget _timeField(String label, TextEditingController controller) => Expanded(
        child: TextFormField(
          controller: controller,
          keyboardType: TextInputType.datetime,
          decoration: InputDecoration(
            labelText: label,
            hintText: 'HH:MM',
            suffixIcon: IconButton(
              tooltip: 'Escolher horário de ${label.toLowerCase()}',
              icon: const Icon(Icons.access_time),
              onPressed: _saving ? null : () => _pickTime(controller),
            ),
          ),
          validator: _validateTime,
          onChanged: (_) => setState(() {}),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final notice = _notice;

    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Novo agendamento' : 'Editar agendamento',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                ),
                DropdownButtonFormField<String>(
                  initialValue: _playlistId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Playlist'),
                  items: [
                    for (final p in widget.playlists)
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (id) => _playlistId = id,
                  validator: (id) =>
                      id == null ? 'Escolha uma playlist.' : null,
                ),
                const SizedBox(height: 16),
                Text('Dias', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final MapEntry(:key, :value) in dayLabels.entries)
                      FilterChip(
                        label: Text(value),
                        selected: _days.contains(key),
                        onSelected: (on) => setState(() {
                          on ? _days.add(key) : _days.remove(key);
                          _daysMissing = false;
                        }),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        _days
                          ..clear()
                          ..addAll(_weekdays);
                        _daysMissing = false;
                      }),
                      child: const Text('Dias úteis'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _days
                          ..clear()
                          ..addAll(dayLabels.keys);
                        _daysMissing = false;
                      }),
                      child: const Text('Todos'),
                    ),
                  ],
                ),
                if (_daysMissing)
                  Text(
                    'Escolha ao menos um dia.',
                    style: TextStyle(color: scheme.error),
                  ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _timeField('Início', _start),
                    const SizedBox(width: 12),
                    _timeField('Fim', _end),
                  ],
                ),
                if (notice != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      notice,
                      style: TextStyle(color: scheme.tertiary),
                    ),
                  ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _priority,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Prioridade (0 a 100)',
                    helperText: 'Maior vence quando dois agendamentos '
                        'coincidem.',
                  ),
                  validator: (value) {
                    final n = int.tryParse((value ?? '').trim());
                    return n == null || n < 0 || n > maxSchedulePriority
                        ? 'Use um número de 0 a $maxSchedulePriority.'
                        : null;
                  },
                ),
                if (_error case final error?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error, style: TextStyle(color: scheme.error)),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
