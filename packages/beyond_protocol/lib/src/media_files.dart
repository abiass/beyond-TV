/// Arquivos de mídia (imagem e vídeo): tipos aceitos, limites e caminhos.
library;

import 'content.dart';

/// MIME aceitos no upload, por tipo de mídia.
///
/// O servidor confere o `Content-Type` declarado e os primeiros bytes do
/// arquivo; os dois precisam bater.
const allowedImageMimes = {
  'image/png',
  'image/jpeg',
  'image/webp',
  'image/gif',
};
const allowedVideoMimes = {'video/mp4', 'video/webm'};

/// Tamanho máximo de uma imagem enviada.
const maxImageBytes = 25 * 1024 * 1024;

/// Tamanho máximo de um vídeo enviado.
const maxVideoBytes = 500 * 1024 * 1024;

/// O [MediaKinds] correspondente a [mime], ou `null` se o tipo não é aceito.
String? mediaKindForMime(String mime) {
  final normalized = mime.split(';').first.trim().toLowerCase();
  if (allowedImageMimes.contains(normalized)) return MediaKinds.image;
  if (allowedVideoMimes.contains(normalized)) return MediaKinds.video;
  return null;
}

/// Limite de tamanho para um arquivo do tipo [kind].
int maxBytesForKind(String kind) =>
    kind == MediaKinds.video ? maxVideoBytes : maxImageBytes;

/// Indica se [value] é um sha256 em hexadecimal minúsculo (64 caracteres).
bool isSha256Hex(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

/// Caminho de download do arquivo da mídia [mediaId], relativo ao servidor.
///
/// Aceita a sessão do admin (cookie) ou o token da TV (`Authorization`).
String mediaFilePath(String mediaId) =>
    '/api/v1/media/${Uri.encodeComponent(mediaId)}/file';
