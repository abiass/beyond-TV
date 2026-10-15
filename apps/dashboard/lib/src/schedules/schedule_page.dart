import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../api/groups.dart';
import '../api/playlists.dart';
import '../api/schedules.dart';
import '../auth/auth_controller.dart';
import '../devices/devices_controller.dart';
import '../groups/groups_controller.dart';
import '../playlists/playlists_controller.dart';
import '../router.dart';
import '../widgets/name_dialog.dart';
import 'schedule_dialog.dart';
import 'schedule_format.dart';
import 'schedules_controller.dart';
import 'week_grid.dart';

/// Agenda semanal de uma TV ou de um grupo.
class SchedulePage extends ConsumerStatefulWidget {
  const SchedulePage({this.deviceId, this.groupId, super.key});

  /// Alvo inicial (vindo do detalhe da TV ou do grupo).
  final String? deviceId;
  final int? groupId;

  @override
  ConsumerState<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends ConsumerState<SchedulePage> {
  late ScheduleTarget? _target =
      widget.deviceId == null && widget.groupId == null
          ? null
          : (
              deviceId: widget.deviceId,
              groupId: widget.deviceId == null ? widget.groupId : null
            );

  Future<void> _edit(
    List<PlaylistSummary> playlists, {
    Schedule? existing,
  }) async {
    final target = _target!;
    final api = ref.read(apiClientProvider);
    await showScheduleDialog(
      context,
      playlists: playlists,
      existing: existing,
      deviceId: target.deviceId,
      groupId: target.groupId,
      onSave: (schedule) async {
        if (existing == null) {
          await api.createSchedule(schedule);
        } else {
          await api.updateSchedule(existing.id, schedule);
        }
        ref.invalidate(schedulesProvider);
      },
    );
  }

  Future<void> _delete(Schedule schedule) async {
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(apiClientProvider);
    final ok = await confirmDialog(
      context,
      title: 'Apagar agendamento',
      message: '"${schedule.name}" será apagado.',
      confirmLabel: 'Apagar',
    );
    if (!ok) return;
    try {
      await api.deleteSchedule(schedule.id);
      ref.invalidate(schedulesProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(devicesProvider).value;
    final groups = ref.watch(groupsProvider).value;
    final playlists = ref.watch(playlistsProvider).value ?? const [];
    final target = _target;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(Routes.home)),
        title: const Text('Agenda'),
      ),
      floatingActionButton: target == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(playlists),
              icon: const Icon(Icons.add),
              label: const Text('Novo agendamento'),
            ),
      body: devices == null || groups == null
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  children: [
                    _TargetPicker(
                      devices: devices,
                      groups: groups,
                      selected: target,
                      onSelected: (t) => setState(() => _target = t),
                    ),
                    const SizedBox(height: 16),
                    if (target == null)
                      const Center(
                        child: Text('Escolha uma TV ou um grupo.'),
                      )
                    else
                      _Body(
                        target: target,
                        playlists: playlists,
                        onEdit: (s) => _edit(playlists, existing: s),
                        onDelete: _delete,
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _TargetPicker extends StatelessWidget {
  const _TargetPicker({
    required this.devices,
    required this.groups,
    required this.selected,
    required this.onSelected,
  });

  final List<DeviceSummary> devices;
  final List<Group> groups;
  final ScheduleTarget? selected;
  final void Function(ScheduleTarget target) onSelected;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: DropdownMenu<ScheduleTarget>(
          width: 360,
          label: const Text('TV ou grupo'),
          initialSelection: selected,
          requestFocusOnTap: false,
          dropdownMenuEntries: [
            for (final d in devices)
              DropdownMenuEntry(
                value: (deviceId: d.id, groupId: null),
                label: 'TV: ${d.name}',
              ),
            for (final g in groups)
              DropdownMenuEntry(
                value: (deviceId: null, groupId: g.id),
                label: 'Grupo: ${g.name}',
              ),
          ],
          onSelected: (t) {
            if (t != null) onSelected(t);
          },
        ),
      );
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.target,
    required this.playlists,
    required this.onEdit,
    required this.onDelete,
  });

  final ScheduleTarget target;
  final List<PlaylistSummary> playlists;
  final void Function(Schedule schedule) onEdit;
  final void Function(Schedule schedule) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedules = ref.watch(schedulesProvider(target));

    return switch (schedules) {
      AsyncData(:final value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Crie uma playlist antes de agendar.'),
              ),
            WeekGrid(schedules: value, onTap: onEdit),
            const SizedBox(height: 24),
            Text(
              'Agendamentos',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (value.isEmpty) const Text('Nenhum agendamento.'),
            for (var i = 0; i < value.length; i++)
              _ScheduleCard(
                schedule: value[i],
                color: scheduleColor(i),
                playlistName: playlists
                    .where((p) => p.id == value[i].playlistId)
                    .firstOrNull
                    ?.name,
                onEdit: () => onEdit(value[i]),
                onDelete: () => onDelete(value[i]),
              ),
          ],
        ),
      AsyncError(:final error) => Center(
          child: Column(
            children: [
              Text(
                error is ApiException
                    ? error.message
                    : 'Não foi possível carregar os agendamentos.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.invalidate(schedulesProvider(target)),
                child: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.schedule,
    required this.color,
    required this.playlistName,
    required this.onEdit,
    required this.onDelete,
  });

  final Schedule schedule;
  final Color color;
  final String? playlistName;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(Icons.square_rounded, color: color),
          title: Text(
            schedule.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${playlistName ?? 'Playlist removida'}\n'
            '${describeSchedule(schedule)}',
          ),
          isThreeLine: true,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
              ),
              IconButton(
                tooltip: 'Apagar',
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      );
}
