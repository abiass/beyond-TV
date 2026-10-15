import 'package:beyond_dashboard/src/audit/describe_audit.dart';
import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

String d(String method, String path) => describeAudit(
      AuditEntry(
        id: 1,
        at: DateTime.utc(2026, 10, 1),
        method: method,
        path: path,
        status: 200,
      ),
    );

void main() {
  test('rotas conhecidas', () {
    const cases = {
      ('POST', '/api/v1/setup'): 'Configuração inicial',
      ('POST', '/api/v1/auth/login'): 'Login',
      ('POST', '/api/v1/auth/logout'): 'Saiu',
      ('POST', '/api/v1/pairing-codes'): 'Gerou código de pareamento',
      ('POST', '/api/v1/pair'): 'TV pareada',
      ('POST', '/api/v1/pair-requests'): 'TV pediu aprovação',
      ('POST', '/api/v1/pair-requests/r1/approve'): 'Aprovou TV',
      ('POST', '/api/v1/pair-requests/r1/reject'): 'Recusou TV',
      ('DELETE', '/api/v1/pair-requests/r1'): 'TV desistiu do pareamento',
      ('PATCH', '/api/v1/devices/abc'): 'Renomeou/alterou TV',
      ('DELETE', '/api/v1/devices/abc'): 'Removeu TV',
      ('PUT', '/api/v1/devices/abc/content'): 'Trocou o conteúdo da TV',
      ('POST', '/api/v1/devices/abc/commands'): 'Enviou comando para a TV',
      ('DELETE', '/api/v1/device'): 'TV se despareou',
      ('POST', '/api/v1/media/files'): 'Enviou arquivo',
      ('POST', '/api/v1/media'): 'Adicionou site',
      ('PATCH', '/api/v1/media/m1'): 'Alterou mídia',
      ('DELETE', '/api/v1/media/m1'): 'Apagou mídia',
      ('POST', '/api/v1/playlists'): 'Criou playlist',
      ('PATCH', '/api/v1/playlists/p1'): 'Alterou playlist',
      ('DELETE', '/api/v1/playlists/p1'): 'Apagou playlist',
      ('PUT', '/api/v1/playlists/p1/items'): 'Alterou itens da playlist',
      ('POST', '/api/v1/groups'): 'Criou grupo',
      ('PATCH', '/api/v1/groups/3'): 'Alterou grupo',
      ('DELETE', '/api/v1/groups/3'): 'Apagou grupo',
      ('PUT', '/api/v1/groups/3/devices'): 'Alterou membros do grupo',
      ('PUT', '/api/v1/groups/3/content'): 'Trocou o conteúdo do grupo',
      ('POST', '/api/v1/schedules'): 'Criou agendamento',
      ('PATCH', '/api/v1/schedules/s1'): 'Alterou agendamento',
      ('DELETE', '/api/v1/schedules/s1'): 'Apagou agendamento',
    };
    for (final MapEntry(key: (method, path), value: text) in cases.entries) {
      expect(d(method, path), text, reason: '$method $path');
    }
  });

  test('rota desconhecida mostra método e caminho', () {
    expect(d('POST', '/api/v1/coisa/nova'), 'POST /api/v1/coisa/nova');
    expect(d('GET', '/api/v1/devices/abc'), 'GET /api/v1/devices/abc');
  });
}
