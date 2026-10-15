import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/media.dart';
import '../auth/auth_controller.dart';

/// Biblioteca de mídia (sites, imagens e vídeos).
final mediaProvider =
    AsyncNotifierProvider.autoDispose<MediaController, List<Media>>(
  MediaController.new,
);

class MediaController extends AsyncNotifier<List<Media>> {
  @override
  Future<List<Media>> build() => ref.read(apiClientProvider).listMedia();

  List<Media> get _current => state.value ?? const [];

  /// Coloca [media] no topo, trocando a versão antiga se já existia.
  void _put(Media media) {
    state = AsyncData([media, ..._current.where((m) => m.id != media.id)]);
  }

  /// Envia um arquivo. Lança `ApiException` em caso de erro.
  Future<Media> upload(
    Uint8List bytes, {
    required String mime,
    String? name,
  }) async {
    final media = await ref
        .read(apiClientProvider)
        .uploadMedia(bytes, mime: mime, name: name);
    _put(media);
    return media;
  }

  Future<Media> addSite(String url, {String? name}) async {
    final media = await ref.read(apiClientProvider).createSite(url, name: name);
    _put(media);
    return media;
  }

  Future<void> rename(String id, String name) async {
    final updated = await ref.read(apiClientProvider).renameMedia(id, name);
    state = AsyncData([
      for (final m in _current) m.id == id ? updated : m,
    ]);
  }

  Future<void> delete(String id) async {
    await ref.read(apiClientProvider).deleteMedia(id);
    state = AsyncData([
      for (final m in _current)
        if (m.id != id) m,
    ]);
  }
}
