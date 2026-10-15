import '../http/json.dart';
import '../media/media_store.dart';
import '../media/media_validation.dart';
import '../playlists/playlist_store.dart';

/// O conteúdo padrão escolhido num `PUT .../content`: uma mídia ou uma
/// playlist (ambas `null` limpa).
typedef ContentChoice = ({String? mediaId, String? playlistId});

/// Valida o corpo de `PUT /devices/<id>/content` e `PUT /groups/<id>/content`.
///
/// Aceita exatamente um entre `mediaId`, `url` (cria ou reaproveita a mídia)
/// e `playlistId`.
ContentChoice parseContentChoice(
  Map<String, Object?> body, {
  required MediaStore media,
  required PlaylistStore playlists,
}) {
  final hasMediaId = body.containsKey('mediaId');
  final hasUrl = body['url'] != null;
  final hasPlaylistId = body.containsKey('playlistId');
  if ([hasMediaId, hasUrl, hasPlaylistId].where((has) => has).length != 1) {
    throw const ApiException.badRequest(
      'Informe "mediaId", "url" ou "playlistId" (apenas um).',
    );
  }

  if (hasUrl) {
    final url = validateUrl(body['url']);
    final name = body['name'] == null ? null : validateMediaName(body['name']);
    final id =
        (media.findByUrl(url) ?? media.createUrl(url: url, name: name)).id;
    return (mediaId: id, playlistId: null);
  }
  if (hasPlaylistId) {
    final value = body['playlistId'];
    if (value != null && value is! String) {
      throw const ApiException.badRequest('Campo "playlistId" inválido.');
    }
    if (value != null && playlists.find(value as String) == null) {
      throw const ApiException.notFound('Playlist não encontrada.');
    }
    return (mediaId: null, playlistId: value as String?);
  }
  final value = body['mediaId'];
  if (value != null && value is! String) {
    throw const ApiException.badRequest('Campo "mediaId" inválido.');
  }
  if (value != null && media.find(value as String) == null) {
    throw const ApiException.notFound('Mídia não encontrada.');
  }
  return (mediaId: value as String?, playlistId: null);
}
