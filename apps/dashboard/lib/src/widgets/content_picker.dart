import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/media.dart';
import '../api/playlists.dart';
import '../media/media_controller.dart';
import '../playlists/playlists_controller.dart';

/// Escolha do conteúdo padrão de uma TV ou de um grupo: site avulso, mídia
/// da biblioteca ou playlist, mais "parar de exibir".
///
/// Cada callback grava na API; se lançar [ApiException], a mensagem aparece
/// abaixo do campo.
class ContentPicker extends ConsumerStatefulWidget {
  const ContentPicker({
    required this.assigned,
    required this.hasContent,
    required this.stopMessage,
    required this.showLabel,
    required this.onUrl,
    required this.onMedia,
    required this.onPlaylist,
    required this.onClear,
    this.initialUrl,
    this.urlSavedMessage = 'Conteúdo enviado.',
    super.key,
  });

  /// O que está atribuído agora (`null` = nada).
  final String? assigned;
  final bool hasContent;

  /// Texto do diálogo de "Parar de exibir".
  final String stopMessage;

  /// Rótulo do botão de exibir o site (ex.: "Exibir nesta TV").
  final String showLabel;
  final String? initialUrl;

  /// Aviso depois de salvar o site.
  final String urlSavedMessage;

  final Future<void> Function(String url, String? name) onUrl;
  final Future<void> Function(Media media) onMedia;
  final Future<void> Function(PlaylistSummary playlist) onPlaylist;
  final Future<void> Function() onClear;

  @override
  ConsumerState<ContentPicker> createState() => _ContentPickerState();
}

class _ContentPickerState extends ConsumerState<ContentPicker> {
  final _formKey = GlobalKey<FormState>();
  late final _url = TextEditingController(text: widget.initialUrl);
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
  Future<bool> _run(Future<void> Function() call) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await call();
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
    final messenger = ScaffoldMessenger.of(context);
    final name = _name.text.trim();
    final url = _url.text.trim();
    final saved = widget.urlSavedMessage;
    final ok = await _run(() => widget.onUrl(url, name.isEmpty ? null : name));
    if (!ok) return;
    messenger.showSnackBar(SnackBar(content: Text(saved)));
  }

  Future<void> _pick(Media media) async {
    final ok = await _run(() => widget.onMedia(media));
    if (ok && mounted) _url.text = media.url ?? '';
  }

  Future<void> _pickPlaylist(PlaylistSummary playlist) async {
    final ok = await _run(() => widget.onPlaylist(playlist));
    if (ok && mounted) _url.clear();
  }

  Future<void> _stop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Parar de exibir'),
        content: Text(widget.stopMessage),
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
    final ok = await _run(widget.onClear);
    if (ok && mounted) _url.clear();
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(mediaProvider).value ?? const <Media>[];
    final playlists = ref.watch(playlistsProvider).value ?? const [];
    final assigned = widget.assigned;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
              label: Text(widget.showLabel),
            ),
            if (widget.hasContent)
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
