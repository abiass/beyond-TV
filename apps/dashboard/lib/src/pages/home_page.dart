import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../auth/auth_controller.dart';
import '../devices/devices_controller.dart';
import '../devices/format_relative.dart';
import '../devices/remove_device_dialog.dart';
import '../devices/rename_device_dialog.dart';
import '../pairing/add_tv_dialog.dart';
import '../realtime/admin_events.dart';
import '../router.dart';
import '../theme.dart';

/// Página inicial do painel: a lista de TVs com status ao vivo.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final username = switch (ref.watch(authProvider)) {
      AsyncData(value: SignedIn(:final username)) => username,
      _ => '',
    };
    final live = ref.watch(adminConnectedProvider).value ?? false;
    final devices = ref.watch(devicesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.tv, color: brandAccent),
            SizedBox(width: 8),
            Flexible(child: Text('Beyond TV', overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Mídia',
            icon: const Icon(Icons.perm_media_outlined),
            onPressed: () => context.go(Routes.media),
          ),
          IconButton(
            tooltip: 'Playlists',
            icon: const Icon(Icons.playlist_play),
            onPressed: () => context.go(Routes.playlists),
          ),
          IconButton(
            tooltip: 'Grupos',
            icon: const Icon(Icons.workspaces_outline),
            onPressed: () => context.go(Routes.groups),
          ),
          IconButton(
            tooltip: 'Agenda',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => context.go(Routes.schedule),
          ),
          const SizedBox(width: 8),
          _LiveIndicator(live: live),
          const SizedBox(width: 16),
          Center(child: Text(username)),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: devices.hasValue && devices.value!.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => showAddTvDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Adicionar TV'),
            )
          : null,
      body: switch (devices) {
        AsyncData(:final value) when value.isEmpty => const _EmptyState(),
        AsyncData(:final value) => _DeviceList(devices: sortDevices(value)),
        AsyncError(:final error) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  error is ApiException
                      ? error.message
                      : 'Não foi possível carregar as TVs.',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(devicesProvider),
                  child: const Text('Tentar de novo'),
                ),
              ],
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

/// Online primeiro, depois por nome (sem diferenciar maiúsculas).
List<DeviceSummary> sortDevices(List<DeviceSummary> devices) =>
    [...devices]..sort((a, b) {
        if (a.online != b.online) return a.online ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator({required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    final color = live ? Colors.green : Colors.grey;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 6),
          Text(
            live ? 'Ao vivo' : 'Reconectando…',
            style: TextStyle(color: live ? null : Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Nenhuma TV pareada ainda.', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Instale o app Beyond TV na TV e clique em "Adicionar TV".',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => showAddTvDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Adicionar TV'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({required this.devices});

  final List<DeviceSummary> devices;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            itemCount: devices.length,
            itemBuilder: (context, i) => _DeviceTile(device: devices[i]),
          ),
        ),
      );
}

/// Texto de apoio da TV: modelo, versão do Android e "visto há…".
String deviceSubtitle(DeviceSummary device, DateTime now) {
  final info = device.info;
  final model = [info?.manufacturer, info?.model].nonNulls.join(' ');
  final parts = [
    if (model.isNotEmpty) model,
    if (info?.androidVersion case final version?) 'Android $version',
  ];
  final hardware = parts.join(' · ');
  if (device.online) return hardware;
  final seen = device.lastSeenAt;
  final lastSeen =
      seen == null ? 'nunca conectou' : 'visto ${formatRelative(seen, now)}';
  return [if (hardware.isNotEmpty) hardware, lastSeen].join(' · ');
}

enum _Action { rename, remove }

class _DeviceTile extends ConsumerWidget {
  const _DeviceTile({required this.device});

  final DeviceSummary device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = device.online ? 'online' : 'offline';
    final subtitle = deviceSubtitle(device, clock.now());
    final item = device.online ? device.currentItem : null;

    return Card(
      child: ListTile(
        onTap: () => context.go(Routes.device(device.id)),
        leading: Tooltip(
          message: status,
          child: Semantics(
            label: status,
            child: Icon(
              Icons.circle,
              size: 14,
              color: device.online ? Colors.green : Colors.grey,
            ),
          ),
        ),
        title: Text(
          device.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle.isNotEmpty) Text(subtitle),
            if (item != null)
              Text(item, maxLines: 1, overflow: TextOverflow.ellipsis),
            Row(
              children: [
                const Icon(Icons.public, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    device.playlist != null
                        ? 'Playlist: ${device.playlist!.name}'
                        : device.content?.name ?? 'Sem conteúdo',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<_Action>(
          tooltip: 'Ações',
          onSelected: (action) => switch (action) {
            _Action.rename => showRenameDeviceDialog(context, device),
            _Action.remove => showRemoveDeviceDialog(context, device),
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: _Action.rename, child: Text('Renomear')),
            PopupMenuItem(value: _Action.remove, child: Text('Remover')),
          ],
        ),
      ),
    );
  }
}
