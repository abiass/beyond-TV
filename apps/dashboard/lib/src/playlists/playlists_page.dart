import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../api/playlists.dart';
import '../router.dart';
import '../widgets/name_dialog.dart';
import 'playlists_controller.dart';

enum _Action { rename, delete }

/// Lista de playlists: criar, renomear, apagar e abrir o editor.
class PlaylistsPage extends ConsumerWidget {
  const PlaylistsPage({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(playlistsProvider.notifier);
    final router = GoRouter.of(context);
    String? createdId;
    final ok = await showNameDialog(
      context,
      title: 'Nova playlist',
      confirmLabel: 'Criar',
      onSave: (name) async => createdId = (await controller.create(name)).id,
    );
    if (ok && createdId != null) router.go(Routes.playlist(createdId!));
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PlaylistSummary playlist,
  ) async {
    final controller = ref.read(playlistsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirmDialog(
      context,
      title: 'Apagar playlist',
      message: '"${playlist.name}" será apagada. As TVs que a exibem vão '
          'ficar sem conteúdo. As mídias continuam na biblioteca.',
      confirmLabel: 'Apagar',
    );
    if (!ok) return;
    try {
      await controller.delete(playlist.id);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(Routes.home)),
        title: const Text('Playlists'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nova playlist'),
      ),
      body: switch (playlists) {
        AsyncData(:final value) when value.isEmpty => const Center(
            child: Text('Nenhuma playlist ainda.'),
          ),
        AsyncData(:final value) => Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                itemCount: value.length,
                itemBuilder: (context, i) {
                  final p = value[i];
                  return Card(
                    child: ListTile(
                      onTap: () => context.go(Routes.playlist(p.id)),
                      leading: const Icon(Icons.playlist_play),
                      title: Text(
                        p.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        p.itemCount == 1 ? '1 item' : '${p.itemCount} itens',
                      ),
                      trailing: PopupMenuButton<_Action>(
                        tooltip: 'Ações',
                        onSelected: (action) => switch (action) {
                          _Action.rename => showNameDialog(
                              context,
                              title: 'Renomear playlist',
                              confirmLabel: 'Salvar',
                              initial: p.name,
                              onSave: (name) => ref
                                  .read(playlistsProvider.notifier)
                                  .rename(p.id, name),
                            ),
                          _Action.delete => _delete(context, ref, p),
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: _Action.rename,
                            child: Text('Renomear'),
                          ),
                          PopupMenuItem(
                            value: _Action.delete,
                            child: Text('Apagar'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        AsyncError(:final error) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  error is ApiException
                      ? error.message
                      : 'Não foi possível carregar as playlists.',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(playlistsProvider),
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
