import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../api/media.dart';
import '../router.dart';
import '../widgets/name_dialog.dart';
import 'add_site_dialog.dart';
import 'file_picker.dart';
import 'format_bytes.dart';
import 'media_controller.dart';
import 'media_thumb.dart';

enum _Action { rename, delete }

/// Biblioteca de mídia: envio de imagens e vídeos, sites salvos.
class MediaLibraryPage extends ConsumerStatefulWidget {
  const MediaLibraryPage({super.key});

  @override
  ConsumerState<MediaLibraryPage> createState() => _MediaLibraryPageState();
}

class _MediaLibraryPageState extends ConsumerState<MediaLibraryPage> {
  bool _uploading = false;
  String? _error;

  Future<void> _upload() async {
    final picker = ref.read(filePickerProvider);
    final controller = ref.read(mediaProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _uploading = true;
      _error = null;
    });
    String? error;
    try {
      final file = await picker.pick(
        acceptedMimes: [...allowedImageMimes, ...allowedVideoMimes],
      );
      if (file == null) return;

      final mime = file.mime.isEmpty ? mimeFromFileName(file.name) : file.mime;
      final kind = mediaKindForMime(mime);
      if (kind == null) {
        error = 'Tipo de arquivo não aceito. Use PNG, JPEG, WebP, GIF, MP4 '
            'ou WebM.';
      } else if (file.bytes.length > maxBytesForKind(kind)) {
        error = 'O arquivo tem ${formatBytes(file.bytes.length)}. O limite '
            'para ${kind == MediaKinds.video ? 'vídeo' : 'imagem'} é '
            '${formatBytes(maxBytesForKind(kind))}.';
      } else {
        await controller.upload(
          file.bytes,
          mime: mime,
          name: defaultMediaName(file.name),
        );
        messenger
            .showSnackBar(const SnackBar(content: Text('Arquivo enviado.')));
      }
    } on ApiException catch (e) {
      error = uploadErrorMessage(e);
    } on Object {
      error = 'Não foi possível ler o arquivo.';
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _error = error;
        });
      }
    }
  }

  Future<void> _rename(Media media) => showNameDialog(
        context,
        title: 'Renomear mídia',
        confirmLabel: 'Salvar',
        initial: media.name,
        onSave: (name) =>
            ref.read(mediaProvider.notifier).rename(media.id, name),
      );

  Future<void> _delete(Media media) async {
    final controller = ref.read(mediaProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirmDialog(
      context,
      title: 'Apagar mídia',
      message: '"${media.name}" será apagada da biblioteca e removida de '
          'todas as playlists e das TVs que a exibem.',
      confirmLabel: 'Apagar',
    );
    if (!ok) return;
    try {
      await controller.delete(media.id);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = ref.watch(mediaProvider);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(Routes.home)),
        title: const Text('Mídia'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _uploading ? null : _upload,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Enviar arquivo'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _uploading ? null : () => showAddSiteDialog(context),
                    icon: const Icon(Icons.public),
                    label: const Text('Adicionar site'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Imagens até ${formatBytes(maxImageBytes)} e vídeos até '
                '${formatBytes(maxVideoBytes)} (PNG, JPEG, WebP, GIF, MP4, '
                'WebM).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_uploading)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              const SizedBox(height: 12),
              switch (media) {
                AsyncData(:final value) when value.isEmpty => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('Nenhuma mídia ainda.')),
                  ),
                AsyncData(:final value) => Column(
                    children: [
                      for (final m in value)
                        _MediaTile(
                          media: m,
                          onAction: (action) => switch (action) {
                            _Action.rename => _rename(m),
                            _Action.delete => _delete(m),
                          },
                        ),
                    ],
                  ),
                AsyncError(:final error) => Column(
                    children: [
                      Text(
                        error is ApiException
                            ? error.message
                            : 'Não foi possível carregar a biblioteca.',
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => ref.invalidate(mediaProvider),
                        child: const Text('Tentar de novo'),
                      ),
                    ],
                  ),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ],
          ),
        ),
      ),
    );
  }
}

/// Mensagem em português para um erro de envio.
String uploadErrorMessage(ApiException e) => switch (e.status) {
      413 => 'O arquivo é maior que o limite aceito pelo servidor.',
      415 => 'O servidor não aceitou este arquivo: o conteúdo não corresponde '
          'a uma imagem ou vídeo suportado.',
      _ => e.message,
    };

/// "Imagem · 180 KB", "Vídeo · 12,4 MB" ou o endereço do site.
String mediaSubtitle(Media media) {
  final size = media.sizeBytes;
  return switch (media.kind) {
    MediaKinds.image =>
      ['Imagem', if (size != null) formatBytes(size)].join(' · '),
    MediaKinds.video =>
      ['Vídeo', if (size != null) formatBytes(size)].join(' · '),
    _ => 'Site · ${media.url ?? ''}',
  };
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.media, required this.onAction});

  final Media media;
  final void Function(_Action) onAction;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: MediaThumb(media: media),
          title: Text(
            media.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            mediaSubtitle(media),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: PopupMenuButton<_Action>(
            tooltip: 'Ações',
            onSelected: onAction,
            itemBuilder: (_) => const [
              PopupMenuItem(value: _Action.rename, child: Text('Renomear')),
              PopupMenuItem(value: _Action.delete, child: Text('Apagar')),
            ],
          ),
        ),
      );
}
