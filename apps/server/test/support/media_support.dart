import 'package:http/http.dart' as http;

import 'test_server.dart';

/// Bytes com a assinatura de cada formato aceito, mais [extra] bytes.
List<int> signed(List<int> signature, [int extra = 8, int seed = 1]) => [
  ...signature,
  for (var i = 0; i < extra; i++) (seed + i) & 0xff,
];

List<int> pngBytes([int seed = 1]) =>
    signed(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], 8, seed);

List<int> jpegBytes([int seed = 1]) =>
    signed(const [0xFF, 0xD8, 0xFF, 0xE0], 8, seed);

List<int> gifBytes() => signed('GIF89a'.codeUnits);

List<int> webpBytes() => [
  ...'RIFF'.codeUnits,
  1,
  2,
  3,
  4,
  ...'WEBP'.codeUnits,
  ...List.filled(4, 0),
];

List<int> mp4Bytes() => [0, 0, 0, 0x18, ...'ftypmp42'.codeUnits, 0, 0, 0, 0];

List<int> webmBytes() => signed(const [0x1A, 0x45, 0xDF, 0xA3]);

/// Envia [bytes] para `POST /api/v1/media/files`.
Future<http.Response> uploadFile(
  TestServer server,
  Map<String, String> admin,
  List<int> bytes, {
  String mime = 'image/png',
  String? name,
}) async {
  final request = http.Request(
    'POST',
    server.uri('/api/v1/media/files${name == null ? '' : '?name=$name'}'),
  )..headers.addAll({'content-type': mime, ...admin});
  request.bodyBytes = bytes;
  return http.Response.fromStream(await request.send());
}
