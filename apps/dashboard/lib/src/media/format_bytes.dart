/// Tamanho legível: "512 B", "180 KB", "12,4 MB".
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  final mb = (bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',');
  return '$mb MB';
}

/// Nome sugerido para o arquivo [fileName]: sem extensão, com até 64
/// caracteres. `null` se sobrar nada (o servidor usa um nome padrão).
String? defaultMediaName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  var name = (dot > 0 ? fileName.substring(0, dot) : fileName).trim();
  if (name.length > 64) name = name.substring(0, 64).trim();
  return name.isEmpty ? null : name;
}

/// MIME deduzido da extensão, para quando o navegador não informa o tipo.
String mimeFromFileName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0) return '';
  return switch (fileName.substring(dot + 1).toLowerCase()) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'mp4' => 'video/mp4',
    'webm' => 'video/webm',
    _ => '',
  };
}
