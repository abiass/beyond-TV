import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../api/media.dart';
import '../auth/auth_controller.dart';
import '../api/playlists.dart';
import '../media/media_controller.dart';
import '../playlists/playlists_controller.dart';
import '../router.dart';
import 'devices_controller.dart';
import 'format_relative.dart';
import 'remove_device_dialog.dart';
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
              _CommandsCard(device: device),
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

class _ContentCard extends ConsumerStatefulWidget {
  const _ContentCard({required this.device});

  final DeviceSummary device;

  @override
  ConsumerState<_ContentCard> createState() => _ContentCardState();
}

class _ContentCardState extends ConsumerState<_ContentCard> {
  final _formKey = GlobalKey<FormState>();
  late final _url = TextEditingController(text: widget.device.content?.url);
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    super.dispose();
  }

  /// Executa [call], mostrando o erro da API abaixo do campo.
  Future<bool> _run(Future<DeviceSummary> Function() call) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await call();
      ref.read(devicesProvider.notifier).replace(updated);
      if (mounted) setState(() => _busy = false);
      return true;
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
      return false;
    }
  }

  Future<void> _show() async {
    if (!_formKey.currentState!.validate()) return;
    final api = ref.read(apiClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    final id = widget.device.id;
    final online = widget.device.online;
    final name = _name.text.trim();
    final ok = await _run(
      () => api.setDeviceContentUrl(
        id,
        _url.text.trim(),
        name: name.isEmpty ? null : name,
      ),
    );
    if (!ok) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          online
              ? 'Conteúdo enviado para a TV.'
              : 'Conteúdo salvo. A TV vai exibir quando conectar.',
        ),
      ),
    );
  }

  Future<void> _pick(Media media) async {
    final api = ref.read(apiClientProvider);
    final ok = await _run(
      () => api.setDeviceMedia(widget.device.id, media.id),
    );
    if (ok && mounted) _url.text = media.url ?? '';
  }

  Future<void> _pickPlaylist(PlaylistSummary playlist) async {
    final api = ref.read(apiClientProvider);
    final ok = await _run(
      () => api.setDevicePlaylist(widget.device.id, playlist.id),
    );
    if (ok && mounted) _url.clear();
  }

  Future<void> _stop() async {
    final api = ref.read(apiClientProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Parar de exibir'),
        content: Text('A TV ${widget.device.name} vai ficar sem conteúdo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Parar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // `mediaId: null` limpa tudo, inclusive a playlist.
    final ok = await _run(() => api.setDeviceMedia(widget.device.id, null));
    if (ok && mounted) _url.clear();
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(mediaProvider).value ?? const <Media>[];
    final playlists = ref.watch(playlistsProvider).value ?? const [];
    final device = widget.device;
    final assigned = device.playlist != null
        ? 'Playlist: ${device.playlist!.name}'
        : device.content?.name;

    return _Section(
      title: 'Conteúdo',
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            assigned == null ? 'Nada atribuído.' : 'Atribuído: $assigned',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _url,
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
            ],
          ),
        ),
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _show,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.public),
              label: const Text('Exibir nesta TV'),
            ),
            if (device.content != null || device.playlist != null)
              OutlinedButton(
                onPressed: _busy ? null : _stop,
                child: const Text('Parar de exibir'),
              ),
          ],
        ),
        if (library.isNotEmpty) ...[
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) => DropdownMenu<Media>(
              width: constraints.maxWidth,
              label: const Text('Mídia da biblioteca'),
              enabled: !_busy,
              dropdownMenuEntries: [
                for (final m in library)
                  DropdownMenuEntry(value: m, label: m.name),
              ],
              onSelected: (m) {
                if (m != null) _pick(m);
              },
            ),
          ),
        ],
        if (playlists.isNotEmpty) ...[
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) => DropdownMenu<PlaylistSummary>(
              width: constraints.maxWidth,
              label: const Text('Playlist'),
              enabled: !_busy,
              dropdownMenuEntries: [
                for (final p in playlists)
                  DropdownMenuEntry(value: p, label: p.name),
              ],
              onSelected: (p) {
                if (p != null) _pickPlaylist(p);
              },
            ),
          ),
        ],
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
