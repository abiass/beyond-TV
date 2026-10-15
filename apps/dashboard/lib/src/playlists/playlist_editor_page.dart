import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../api/media.dart';
import '../api/playlists.dart';
import '../auth/auth_controller.dart';
import '../media/media_controller.dart';
import '../media/media_library_page.dart' show mediaSubtitle;
import '../media/media_thumb.dart';
import '../router.dart';
import '../widgets/name_dialog.dart';
import 'playlists_controller.dart';

/// Uma linha do editor: a mídia e o texto da duração.
class _Row {
  _Row(this.media, int? seconds)
      : duration = TextEditingController(text: seconds?.toString() ?? ''),
        key = UniqueKey();

  final Media media;
  final TextEditingController duration;
  final Key key;

  /// Segundos digitados; `null` se vazio ou inválido (veja [error]).
  int? get seconds => int.tryParse(duration.text.trim());

  /// Mensagem de erro da duração, ou `null` se está válida.
  String? get error {
    if (duration.text.trim().isEmpty) return null;
    return isValidItemDuration(seconds)
        ? null
        : 'Use de $minItemDurationSeconds a $maxItemDurationSeconds s.';
  }
}

/// Editor de uma playlist: itens, ordem e duração de cada um.
class PlaylistEditorPage extends ConsumerStatefulWidget {
  const PlaylistEditorPage({required this.id, super.key});

  final String id;

  @override
  ConsumerState<PlaylistEditorPage> createState() => _PlaylistEditorPageState();
}

class _PlaylistEditorPageState extends ConsumerState<PlaylistEditorPage> {
  List<_Row>? _rows;
  String _saved = '';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final row in _rows ?? const <_Row>[]) {
      row.duration.dispose();
    }
    super.dispose();
  }

  /// Resumo do que está na tela, para saber se há alterações.
  String _signature() => [
        for (final row in _rows ?? const <_Row>[])
          '${row.media.id}:${row.duration.text.trim()}',
      ].join('|');

  bool get _dirty => _rows != null && _signature() != _saved;
  bool get _valid => _rows!.every((row) => row.error == null);

  void _load(Playlist playlist) {
    _rows = [
      for (final e in playlist.items) _Row(e.media, e.durationSeconds),
    ];
    _saved = _signature();
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      _rows!.insert(newIndex, _rows!.removeAt(oldIndex));
    });
  }

  void _remove(int index) {
    setState(() => _rows!.removeAt(index).duration.dispose());
  }

  Future<void> _add() async {
    final room = maxPlaylistItems - _rows!.length;
    final chosen = await showDialog<List<Media>>(
      context: context,
      builder: (_) => _PickMediaDialog(room: room),
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;
    setState(() {
      for (final media in chosen) {
        _rows!.add(_Row(media, null));
      }
    });
  }

  Future<void> _save() async {
    if (!_valid) return;
    final api = ref.read(apiClientProvider);
    final controller = ref.read(playlistsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await api.setPlaylistItems(widget.id, [
        for (final row in _rows!) (row.media.id, row.seconds),
      ]);
      controller.updateFrom(saved);
      messenger.showSnackBar(const SnackBar(content: Text('Playlist salva.')));
      if (mounted) {
        setState(() {
          _saving = false;
          _saved = _signature();
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _back() async {
    final router = GoRouter.of(context);
    if (_dirty) {
      final leave = await confirmDialog(
        context,
        title: 'Sair sem salvar?',
        message: 'As alterações desta playlist serão perdidas.',
        confirmLabel: 'Sair',
      );
      if (!leave) return;
    }
    router.go(Routes.playlists);
  }

  @override
  Widget build(BuildContext context) {
    final playlist = ref.watch(playlistProvider(widget.id));
    // Mantém a lista viva para atualizar a contagem ao salvar.
    ref.watch(playlistsProvider);
    if (_rows == null && playlist.hasValue) _load(playlist.requireValue);

    final leading = BackButton(onPressed: _back);
    if (_rows == null) {
      return Scaffold(
        appBar: AppBar(leading: leading),
        body: switch (playlist) {
          AsyncError(:final error) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    error is ApiException && error.status == 404
                        ? 'Playlist não encontrada.'
                        : error is ApiException
                            ? error.message
                            : 'Não foi possível carregar a playlist.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () =>
                        ref.invalidate(playlistProvider(widget.id)),
                    child: const Text('Tentar de novo'),
                  ),
                ],
              ),
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      );
    }

    final rows = _rows!;
    final name = playlist.value?.name ?? '';
    final dirty = _dirty;

    return Scaffold(
      appBar: AppBar(
        leading: leading,
        title: Text(name + (dirty ? ' •' : '')),
        actions: [
          IconButton(
            tooltip: 'Renomear',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showNameDialog(
              context,
              title: 'Renomear playlist',
              confirmLabel: 'Salvar',
              initial: name,
              onSave: (n) =>
                  ref.read(playlistsProvider.notifier).rename(widget.id, n),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FilledButton(
              onPressed: dirty && _valid && !_saving ? _save : null,
              child: const Text('Salvar'),
            ),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Duração de $minItemDurationSeconds a '
                      '$maxItemDurationSeconds segundos. Vazia: vídeo toca '
                      'até o fim; site e imagem ficam $defaultItemDurationSeconds s '
                      '(ou parados, se for o único item).',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: rows.length >= maxPlaylistItems || _saving
                              ? null
                              : _add,
                          icon: const Icon(Icons.add),
                          label: const Text('Adicionar mídia'),
                        ),
                        Text('${rows.length} de $maxPlaylistItems itens'),
                        if (dirty) ...[
                          const Text('Alterações não salvas'),
                        ],
                      ],
                    ),
                    if (_saving)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(),
                      ),
                    if (_error case final error?)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? const Center(
                        child: Text('Playlist vazia. Adicione mídias.'),
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.all(16),
                        buildDefaultDragHandles: false,
                        itemCount: rows.length,
                        onReorderItem: _reorder,
                        itemBuilder: (context, i) => _ItemTile(
                          key: rows[i].key,
                          index: i,
                          row: rows[i],
                          onChanged: () => setState(() {}),
                          onRemove: () => _remove(i),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.index,
    required this.row,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final int index;
  final _Row row;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.drag_handle),
                ),
              ),
              MediaThumb(media: row.media, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.media.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      mediaSubtitle(row.media),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: row.duration,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Segundos',
                    hintText: row.media.isVideo ? 'até o fim' : 'padrão',
                    errorText: row.error,
                    errorMaxLines: 2,
                    isDense: true,
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
              IconButton(
                tooltip: 'Remover da playlist',
                icon: const Icon(Icons.close),
                onPressed: onRemove,
              ),
            ],
          ),
        ),
      );
}

/// Lista a biblioteca e devolve as mídias marcadas.
class _PickMediaDialog extends ConsumerStatefulWidget {
  const _PickMediaDialog({required this.room});

  /// Quantos itens ainda cabem na playlist.
  final int room;

  @override
  ConsumerState<_PickMediaDialog> createState() => _PickMediaDialogState();
}

class _PickMediaDialogState extends ConsumerState<_PickMediaDialog> {
  final _chosen = <Media>[];

  @override
  Widget build(BuildContext context) {
    final media = ref.watch(mediaProvider);

    return AlertDialog(
      title: const Text('Adicionar mídia'),
      content: SizedBox(
        width: 480,
        child: switch (media) {
          AsyncData(:final value) when value.isEmpty => const Text(
              'A biblioteca está vazia. Envie arquivos na tela Mídia.',
            ),
          AsyncData(:final value) => ListView(
              shrinkWrap: true,
              children: [
                for (final m in value)
                  CheckboxListTile(
                    value: _chosen.contains(m),
                    secondary: MediaThumb(media: m, size: 40),
                    title: Text(m.name, maxLines: 1),
                    subtitle: Text(mediaSubtitle(m), maxLines: 1),
                    onChanged: !_chosen.contains(m) &&
                            _chosen.length >= widget.room
                        ? null
                        : (on) => setState(
                              () => on! ? _chosen.add(m) : _chosen.remove(m),
                            ),
                  ),
              ],
            ),
          AsyncError(:final error) => Text(
              error is ApiException
                  ? error.message
                  : 'Não foi possível carregar a biblioteca.',
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed:
              _chosen.isEmpty ? null : () => Navigator.of(context).pop(_chosen),
          child: Text(
            _chosen.isEmpty ? 'Adicionar' : 'Adicionar (${_chosen.length})',
          ),
        ),
      ],
    );
  }
}
