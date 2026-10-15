import 'dart:convert';

import 'json_fields.dart';
import 'media_files.dart';
import 'playlists.dart';

/// Tipos de mídia (`media.kind`).
abstract final class MediaKinds {
  static const url = 'url';
  static const image = 'image';
  static const video = 'video';
}

/// Tamanho máximo de uma URL de conteúdo.
const maxContentUrlLength = 2048;

/// Indica se [url] pode ser exibida pela TV: só `http`/`https`, com host,
/// sem espaços e até [maxContentUrlLength] caracteres.
///
/// Bloqueia `file:`, `javascript:`, `data:` e afins (veja a seção 10 do
/// plano).
bool isSafeContentUrl(String url) {
  if (url.isEmpty || url.length > maxContentUrlLength) return false;
  if (url.contains(RegExp(r'\s'))) return false;
  final uri = Uri.tryParse(url);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

/// Um item do que a TV deve exibir.
final class ContentItem {
  const ContentItem({
    required this.mediaId,
    required this.kind,
    required this.name,
    this.url,
    this.sha256,
    this.durationSeconds,
  });

  factory ContentItem.fromJson(Map<String, Object?> json) => ContentItem(
        mediaId: json.field<String>('mediaId'),
        kind: json.field<String>('kind'),
        name: json.field<String>('name'),
        url: json.optionalField<String>('url'),
        sha256: json.optionalField<String>('sha256'),
        durationSeconds: json.optionalField<int>('durationSeconds'),
      );

  final String mediaId;

  /// Um dos [MediaKinds].
  final String kind;
  final String name;

  /// Endereço do site, para `kind == url`.
  final String? url;

  /// Hash do arquivo, para imagem e vídeo. A TV baixa o arquivo de
  /// [mediaFilePath] e o guarda em cache com este nome.
  final String? sha256;

  /// Por quanto tempo exibir antes do próximo item.
  ///
  /// `null`: vídeo toca até o fim; site ou imagem fica parado se for o único
  /// item, senão usa [defaultItemDurationSeconds].
  final int? durationSeconds;

  Map<String, Object?> toJson() => {
        'mediaId': mediaId,
        'kind': kind,
        'name': name,
        if (url != null) 'url': url,
        if (sha256 != null) 'sha256': sha256,
        if (durationSeconds != null) 'durationSeconds': durationSeconds,
      };
}

/// Payload do `content.sync`: tudo o que a TV deve exibir agora.
///
/// A TV guarda o último manifesto em disco e continua exibindo se o
/// servidor cair. [revision] muda sempre que [items] muda.
final class ContentManifest {
  ContentManifest({required this.items}) : revision = _revisionOf(items);

  factory ContentManifest.fromJson(Map<String, Object?> json) {
    final manifest = ContentManifest(
      items: [
        for (final item in json.field<List<Object?>>('items'))
          if (item is Map<String, Object?>) ContentItem.fromJson(item),
      ],
    );
    return manifest;
  }

  /// Manifesto vazio: a TV mostra a tela "Aguardando conteúdo".
  static final empty = ContentManifest(items: const []);

  final List<ContentItem> items;

  /// Identifica o conteúdo, calculado a partir de [items].
  final String revision;

  bool get isEmpty => items.isEmpty;

  Map<String, Object?> toJson() => {
        'revision': revision,
        'items': [for (final item in items) item.toJson()],
      };

  static String _revisionOf(List<ContentItem> items) {
    // FNV-1a de 32 bits do JSON dos itens: basta para detectar mudança.
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(
      jsonEncode([
        for (final item in items) item.toJson(),
      ]),
    )) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

/// Comandos que o painel pode mandar para uma TV.
abstract final class DeviceCommands {
  static const reload = 'reload';
  static const identify = 'identify';
  static const unpair = 'unpair';

  static const all = {reload, identify, unpair};
}

/// Payload do `cmd.identify`: a TV mostra [name] em fonte gigante.
final class IdentifyPayload {
  const IdentifyPayload({required this.name, this.durationSeconds = 10});

  factory IdentifyPayload.fromJson(Map<String, Object?> json) =>
      IdentifyPayload(
        name: json.field<String>('name'),
        durationSeconds: json.optionalField<int>('durationSeconds') ?? 10,
      );

  final String name;
  final int durationSeconds;

  Map<String, Object?> toJson() => {
        'name': name,
        'durationSeconds': durationSeconds,
      };
}

/// Payload do `ack`: a TV confirma que recebeu a mensagem [ref].
final class AckPayload {
  const AckPayload({required this.ref});

  factory AckPayload.fromJson(Map<String, Object?> json) =>
      AckPayload(ref: json.field<String>('ref'));

  /// `id` do envelope confirmado.
  final String ref;

  Map<String, Object?> toJson() => {'ref': ref};
}
