import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../api/groups.dart';
import '../api/schedules.dart';
import '../auth/auth_controller.dart';
import '../groups/groups_controller.dart';
import '../router.dart';
import '../schedules/schedule_summary_tile.dart';
import '../schedules/schedules_controller.dart';
import '../widgets/content_picker.dart';
import 'devices_controller.dart';
import 'format_relative.dart';
import 'remove_device_dialog.dart';
import 'screenshot_card.dart';
import 'rename_device_dialog.dart';

enum _Action { rename, remove }

/// Detalhes de uma TV: status, site exibido e comandos.
class DeviceDetailPage extends ConsumerWidget {
  const DeviceDetailPage({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(devicesProvider);
    final device = devices.value?.where((d) => d.id == id).firstOrNull;

    if (device == null) {
      return Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => context.go(Routes.home)),
        ),
        body: switch (devices) {
          AsyncLoading() => const Center(child: CircularProgressIndicator()),
          _ => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('TV não encontrada.'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.go(Routes.home),
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
        leading: BackButton(onPressed: () => context.go(Routes.home)),
        title: Text(device.name),
        actions: [
          PopupMenuButton<_Action>(
            tooltip: 'Ações',
            onSelected: (action) async {
              switch (action) {
                case _Action.rename:
                  await showRenameDeviceDialog(context, device);
                case _Action.remove:
                  final router = GoRouter.of(context);
                  if (await showRemoveDeviceDialog(context, device)) {
                    router.go(Routes.home);
                  }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: _Action.rename, child: Text('Renomear')),
              PopupMenuItem(value: _Action.remove, child: Text('Remover')),
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
              _StatusCard(device: device),
              const SizedBox(height: 12),
              _ContentCard(device: device),
              const SizedBox(height: 12),
              _GroupCard(device: device),
              const SizedBox(height: 12),
              _SchedulesCard(device: device),
              const SizedBox(height: 12),
              _CommandsCard(device: device),
              const SizedBox(height: 12),
              ScreenshotCard(device: device),
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

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.device});

  final DeviceSummary device;

  @override
  Widget build(BuildContext context) {
    final info = device.info;
    final status = device.online ? 'online' : 'offline';
    final seen = device.lastSeenAt;
    final maker = [info?.manufacturer, info?.model].nonNulls.join(' ');
    final width = info?.screenWidth;
    final height = info?.screenHeight;
    final lines = [
      if (maker.isNotEmpty) maker,
      if (info?.androidVersion case final v?) 'Android $v',
      if (info != null) 'App ${info.appVersion}',
      if (width != null && height != null) '$width x $height',
    ];
    final current = device.currentItem;

    return _Section(
      title: 'Status',
      children: [
        Row(
          children: [
            Semantics(
              label: status,
              child: Icon(
                Icons.circle,
                size: 14,
                color: device.online ? Colors.green : Colors.grey,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                [
                  device.online ? 'Online' : 'Offline',
                  if (seen != null)
                    'visto ${formatRelative(seen, clock.now())}',
                ].join(' · '),
              ),
            ),
          ],
        ),
        for (final line in lines) Text(line),
        if (current != null) ...[
          const SizedBox(height: 8),
          const Text('Exibindo agora'),
          Text(current, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ],
    );
  }
}

class _ContentCard extends ConsumerWidget {
  const _ContentCard({required this.device});

  final DeviceSummary device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(apiClientProvider);
    final devices = ref.read(devicesProvider.notifier);
    final id = device.id;

    return _Section(
      title: 'Conteúdo',
      children: [
        ContentPicker(
          assigned: device.playlist != null
              ? 'Playlist: ${device.playlist!.name}'
              : device.content?.name,
          hasContent: device.content != null || device.playlist != null,
          initialUrl: device.content?.url,
          stopMessage: 'A TV ${device.name} vai ficar sem conteúdo.',
          showLabel: 'Exibir nesta TV',
          urlSavedMessage: device.online
              ? 'Conteúdo enviado para a TV.'
              : 'Conteúdo salvo. A TV vai exibir quando conectar.',
          onUrl: (url, name) async => devices
              .replace(await api.setDeviceContentUrl(id, url, name: name)),
          onMedia: (media) async =>
              devices.replace(await api.setDeviceMedia(id, media.id)),
          onPlaylist: (playlist) async =>
              devices.replace(await api.setDevicePlaylist(id, playlist.id)),
          // `mediaId: null` limpa tudo, inclusive a playlist.
          onClear: () async =>
              devices.replace(await api.setDeviceMedia(id, null)),
        ),
      ],
    );
  }
}

class _GroupCard extends ConsumerWidget {
  const _GroupCard({required this.device});

  final DeviceSummary device;

  Future<void> _change(
    BuildContext context,
    WidgetRef ref,
    int? groupId,
  ) async {
    if (groupId == device.groupId) return;
    final messenger = ScaffoldMessenger.of(context);
    final devices = ref.read(devicesProvider.notifier);
    try {
      devices.replace(
        await ref.read(apiClientProvider).setDeviceGroup(device.id, groupId),
      );
      ref.invalidate(groupsProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider).value ?? const <Group>[];
    final group = groups.where((g) => g.id == device.groupId).firstOrNull;

    return _Section(
      title: 'Grupo',
      children: [
        LayoutBuilder(
          builder: (context, constraints) => DropdownMenu<int?>(
            // Recria o campo quando o grupo muda por outro caminho.
            key: ValueKey(group?.id),
            width: constraints.maxWidth,
            label: const Text('Grupo'),
            initialSelection: group?.id,
            requestFocusOnTap: false,
            dropdownMenuEntries: [
              const DropdownMenuEntry<int?>(value: null, label: 'Nenhum'),
              for (final g in groups)
                DropdownMenuEntry<int?>(value: g.id, label: g.name),
            ],
            onSelected: (groupId) => _change(context, ref, groupId),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Conteúdo próprio da TV tem prioridade sobre o do grupo.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _SchedulesCard extends ConsumerWidget {
  const _SchedulesCard({required this.device});

  final DeviceSummary device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final own = ref.watch(
      schedulesProvider((deviceId: device.id, groupId: null)),
    );
    final groupId = device.groupId;
    final inherited = groupId == null
        ? const AsyncData<List<Schedule>>([])
        : ref.watch(schedulesProvider((deviceId: null, groupId: groupId)));

    final failure = own.error ?? inherited.error;
    final loading = own.isLoading || inherited.isLoading;
    final all = [...?own.value, ...?inherited.value]..sort(compareByPrecedence);

    return _Section(
      title: 'Agendamentos',
      children: [
        if (failure != null)
          Text(
            failure is ApiException
                ? failure.message
                : 'Não foi possível carregar os agendamentos.',
          )
        else if (loading && all.isEmpty)
          const LinearProgressIndicator()
        else if (all.isEmpty)
          const Text('Nenhum agendamento.')
        else
          for (final s in all)
            ScheduleSummaryTile(s, origin: s.isDevice ? 'TV' : 'Grupo'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => context.go(Routes.scheduleFor(deviceId: device.id)),
          icon: const Icon(Icons.calendar_month_outlined),
          label: const Text('Abrir agenda'),
        ),
      ],
    );
  }
}

class _CommandsCard extends ConsumerWidget {
  const _CommandsCard({required this.device});

  final DeviceSummary device;

  Future<void> _send(
    BuildContext context,
    WidgetRef ref,
    String type,
    String done,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiClientProvider).sendCommand(device.id, type);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _unpair(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final api = ref.read(apiClientProvider);
    final devices = ref.read(devicesProvider.notifier);
    if (!await confirmRemoveDevice(context, device)) return;
    try {
      await api.sendCommand(device.id, DeviceCommands.unpair);
      await devices.remove(device.id).catchError((Object _) {});
      messenger.showSnackBar(const SnackBar(content: Text('TV removida.')));
      router.go(Routes.home);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = device.online;
    final offlineTip = online ? null : 'A TV está offline';

    return _Section(
      title: 'Comandos',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Tooltip(
              message: offlineTip ?? 'Recarrega o site na TV',
              child: OutlinedButton.icon(
                onPressed: online
                    ? () => _send(
                          context,
                          ref,
                          DeviceCommands.reload,
                          'Recarregando a TV.',
                        )
                    : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Recarregar'),
              ),
            ),
            Tooltip(
              message: offlineTip ?? 'Mostra o nome na tela da TV por 10 s',
              child: OutlinedButton.icon(
                onPressed: online
                    ? () => _send(
                          context,
                          ref,
                          DeviceCommands.identify,
                          'Olhe para a TV.',
                        )
                    : null,
                icon: const Icon(Icons.visibility),
                label: const Text('Identificar'),
              ),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => _unpair(context, ref),
              icon: const Icon(Icons.link_off),
              label: const Text('Desparear'),
            ),
          ],
        ),
      ],
    );
  }
}
