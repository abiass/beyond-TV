import 'package:beyond_protocol/beyond_protocol.dart';

final _rules = <(String, RegExp, String)>[
  ('POST', RegExp(r'^/setup$'), 'Configuração inicial'),
  ('POST', RegExp(r'^/auth/login$'), 'Login'),
  ('POST', RegExp(r'^/auth/logout$'), 'Saiu'),
  ('POST', RegExp(r'^/pairing-codes$'), 'Gerou código de pareamento'),
  ('POST', RegExp(r'^/pair$'), 'TV pareada'),
  ('POST', RegExp(r'^/pair-requests$'), 'TV pediu aprovação'),
  ('POST', RegExp(r'^/pair-requests/[^/]+/approve$'), 'Aprovou TV'),
  ('POST', RegExp(r'^/pair-requests/[^/]+/reject$'), 'Recusou TV'),
  ('DELETE', RegExp(r'^/pair-requests/[^/]+$'), 'TV desistiu do pareamento'),
  ('PATCH', RegExp(r'^/devices/[^/]+$'), 'Renomeou/alterou TV'),
  ('DELETE', RegExp(r'^/devices/[^/]+$'), 'Removeu TV'),
  ('PUT', RegExp(r'^/devices/[^/]+/content$'), 'Trocou o conteúdo da TV'),
  ('POST', RegExp(r'^/devices/[^/]+/commands$'), 'Enviou comando para a TV'),
  ('DELETE', RegExp(r'^/device$'), 'TV se despareou'),
  ('POST', RegExp(r'^/media/files$'), 'Enviou arquivo'),
  ('POST', RegExp(r'^/media$'), 'Adicionou site'),
  ('PATCH', RegExp(r'^/media/[^/]+$'), 'Alterou mídia'),
  ('DELETE', RegExp(r'^/media/[^/]+$'), 'Apagou mídia'),
  ('POST', RegExp(r'^/playlists$'), 'Criou playlist'),
  ('PATCH', RegExp(r'^/playlists/[^/]+$'), 'Alterou playlist'),
  ('DELETE', RegExp(r'^/playlists/[^/]+$'), 'Apagou playlist'),
  ('PUT', RegExp(r'^/playlists/[^/]+/items$'), 'Alterou itens da playlist'),
  ('POST', RegExp(r'^/groups$'), 'Criou grupo'),
  ('PATCH', RegExp(r'^/groups/[^/]+$'), 'Alterou grupo'),
  ('DELETE', RegExp(r'^/groups/[^/]+$'), 'Apagou grupo'),
  ('PUT', RegExp(r'^/groups/[^/]+/devices$'), 'Alterou membros do grupo'),
  ('PUT', RegExp(r'^/groups/[^/]+/content$'), 'Trocou o conteúdo do grupo'),
  ('POST', RegExp(r'^/schedules$'), 'Criou agendamento'),
  ('PATCH', RegExp(r'^/schedules/[^/]+$'), 'Alterou agendamento'),
  ('DELETE', RegExp(r'^/schedules/[^/]+$'), 'Apagou agendamento'),
];

const _prefix = '/api/v1';

/// Frase curta para a linha de auditoria; rota desconhecida vira
/// "MÉTODO /caminho".
String describeAudit(AuditEntry entry) {
  final path = entry.path.startsWith(_prefix)
      ? entry.path.substring(_prefix.length)
      : entry.path;
  for (final (method, pattern, text) in _rules) {
    if (method == entry.method && pattern.hasMatch(path)) return text;
  }
  return '${entry.method} ${entry.path}';
}
