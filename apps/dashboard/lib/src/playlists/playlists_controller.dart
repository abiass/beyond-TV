import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/playlists.dart';
import '../auth/auth_controller.dart';

/// Playlists (resumo), por nome.
final playlistsProvider = AsyncNotifierProvider.autoDispose<PlaylistsController,
    List<PlaylistSummary>>(PlaylistsController.new);

/// Uma playlist com os itens, para o editor.
final playlistProvider = FutureProvider.autoDispose.family<Playlist, String>(
  (ref, id) => ref.watch(apiClientProvider).getPlaylist(id),
);

class PlaylistsController extends AsyncNotifier<List<PlaylistSummary>> {
  @override
  Future<List<PlaylistSummary>> build() =>
      ref.read(apiClientProvider).listPlaylists();

  List<PlaylistSummary> get _current => state.value ?? const [];

  static List<PlaylistSummary> _sorted(List<PlaylistSummary> list) =>
      [...list]..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

  /// Cria a playlist. Lança `ApiException` em caso de erro.
  Future<Playlist> create(String name) async {
    final playlist = await ref.read(apiClientProvider).createPlaylist(name);
    state = AsyncData(_sorted([..._current, playlist.summary]));
    return playlist;
  }

  Future<void> rename(String id, String name) async {
    final updated = await ref.read(apiClientProvider).renamePlaylist(id, name);
    state = AsyncData(
      _sorted([
        for (final p in _current)
          p.id == id
              ? PlaylistSummary(
                  id: id,
                  name: updated.name,
                  itemCount: p.itemCount,
                  createdAt: p.createdAt,
                )
              : p,
      ]),
    );
    ref.invalidate(playlistProvider(id));
  }

  Future<void> delete(String id) async {
    await ref.read(apiClientProvider).deletePlaylist(id);
    state = AsyncData([
      for (final p in _current)
        if (p.id != id) p,
    ]);
  }

  /// Atualiza a quantidade de itens depois de salvar o editor.
  void updateFrom(Playlist playlist) {
    state = AsyncData(
      _sorted([
        for (final p in _current) p.id == playlist.id ? playlist.summary : p,
      ]),
    );
  }
}
