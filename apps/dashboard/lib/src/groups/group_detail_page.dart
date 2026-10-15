import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../api/groups.dart';
import '../auth/auth_controller.dart';
import '../devices/devices_controller.dart';
import '../router.dart';
import '../schedules/schedule_summary_tile.dart';
import '../schedules/schedules_controller.dart';
import '../widgets/content_picker.dart';
import 'groups_controller.dart';
import 'groups_page.dart';

enum _Action { rename, delete }

/// Detalhe do grupo: membros, conteúdo padrão e agendamentos.
class GroupDetailPage extends ConsumerWidget {
  const GroupDetailPage({required this.id, super.key});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider);
    final group = groups.value?.where((g) => g.id == id).firstOrNull;

    if (group == null) {
      return Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => context.go(Routes.groups)),
        ),
        body: switch (groups) {
          AsyncLoading() => const Center(child: CircularProgressIndicator()),
          _ => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Grupo não encontrado.'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.go(Routes.groups),
                    child: const Text('Voltar para a lista'),
                  ),
                ],
              ),
            ),
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(Routes.groups)),
        title: Text(group.name),
        actions: [
          PopupMenuButton<_Action>(
            tooltip: 'Ações',
            onSelected: (action) async {
              switch (action) {
                case _Action.rename:
                  await renameGroupDialog(context, ref, group);
                case _Action.delete:
                  final router = GoRouter.of(context);
                  if (await deleteGroupWithConfirm(context, ref, group)) {
                    router.go(Routes.groups);
                  }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: _Action.rename, child: Text('Renomear')),
              PopupMenuItem(value: _Action.delete, child: Text('Apagar')),
            ],
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _MembersCard(key: ValueKey(group.id), group: group),
              const SizedBox(height: 12),
              _ContentCard(group: group),
              const SizedBox(height: 12),
              _SchedulesCard(group: group),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );
}

class _MembersCard extends ConsumerStatefulWidget {
  const _MembersCard({required this.group, super.key});

  final Group group;

  @override
  ConsumerState<_MembersCard> createState() => _MembersCardState();
}

class _MembersCardState extends ConsumerState<_MembersCard> {
  late final Set<String> _selected = {...widget.group.deviceIds};
  bool _busy = false;

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(groupsProvider.notifier);
    setState(() => _busy = true);
    try {
      await controller.setMembers(widget.group.id, _selected.toList()..sort());
      messenger.showSnackBar(const SnackBar(content: Text('Membros salvos.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(devicesProvider).value ?? const <DeviceSummary>[];
    final groups = ref.watch(groupsProvider).value ?? const <Group>[];
    final names = {for (final g in groups) g.id: g.name};

    return _Section(
      title: 'TVs do grupo',
      children: [
        if (devices.isEmpty) const Text('Nenhuma TV pareada.'),
        for (final d in devices)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _selected.contains(d.id),
            onChanged: _busy
                ? null
                : (checked) => setState(() {
                      if (checked ?? false) {
                        _selected.add(d.id);
                      } else {
                        _selected.remove(d.id);
                      }
                    }),
            title: Text(d.name),
            subtitle: Text(
              [
                d.online ? 'Online' : 'Offline',
                if (d.groupId != null &&
                    d.groupId != widget.group.id &&
                    _selected.contains(d.id))
                  'sai de "${names[d.groupId] ?? 'outro grupo'}"',
              ].join(' · '),
            ),
            secondary: Icon(
              Icons.circle,
              size: 14,
              color: d.online ? Colors.green : Colors.grey,
            ),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Salvar membros'),
          ),
        ),
      ],
    );
  }
}

class _ContentCard extends ConsumerWidget {
  const _ContentCard({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(apiClientProvider);
    final groups = ref.read(groupsProvider.notifier);
    final id = group.id;

    return _Section(
      title: 'Conteúdo padrão',
      children: [
        Text(
          'Vale para as TVs do grupo que não têm conteúdo próprio.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        ContentPicker(
          assigned: group.contentLabel,
          hasContent: group.content != null || group.playlist != null,
          initialUrl: group.content?.url,
          stopMessage: 'O grupo ${group.name} vai ficar sem conteúdo padrão.',
          showLabel: 'Exibir neste grupo',
          urlSavedMessage: 'Conteúdo do grupo salvo.',
          onUrl: (url, name) async => groups
              .replace(await api.setGroupContent(id, url: url, name: name)),
          onMedia: (media) async =>
              groups.replace(await api.setGroupContent(id, mediaId: media.id)),
          onPlaylist: (playlist) async => groups
              .replace(await api.setGroupContent(id, playlistId: playlist.id)),
          onClear: () async => groups.replace(await api.setGroupContent(id)),
        ),
      ],
    );
  }
}

class _SchedulesCard extends ConsumerWidget {
  const _SchedulesCard({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedules = ref.watch(
      schedulesProvider((deviceId: null, groupId: group.id)),
    );

    return _Section(
      title: 'Agendamentos',
      children: [
        switch (schedules) {
          AsyncData(:final value) when value.isEmpty =>
            const Text('Nenhum agendamento.'),
          AsyncData(:final value) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final s in value) ScheduleSummaryTile(s)],
            ),
          AsyncError(:final error) => Text(
              error is ApiException
                  ? error.message
                  : 'Não foi possível carregar os agendamentos.',
            ),
          _ => const LinearProgressIndicator(),
        },
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => context.go(Routes.scheduleFor(groupId: group.id)),
          icon: const Icon(Icons.calendar_month_outlined),
          label: const Text('Abrir agenda'),
        ),
      ],
    );
  }
}
