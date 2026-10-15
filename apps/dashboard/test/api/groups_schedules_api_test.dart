import 'dart:convert';

import 'package:beyond_dashboard/src/api/api_client.dart';
import 'package:beyond_dashboard/src/api/groups.dart';
import 'package:beyond_dashboard/src/api/schedules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _groupJson = {
  'id': 3,
  'name': 'Recepção',
  'deviceIds': ['a', 'b'],
  'content': null,
  'playlist': {'id': 'p1', 'name': 'Manhã'},
  'createdAt': '2026-10-01T10:00:00.000Z',
};
const _scheduleJson = {
  'id': 's1',
  'name': 'Almoço',
  'playlistId': 'p1',
  'deviceId': null,
  'groupId': 3,
  'days': [1, 2, 3, 4, 5],
  'start': '11:00',
  'end': '14:00',
  'priority': 10,
  'createdAt': '2026-10-01T10:00:00.000Z',
};

void main() {
  final base = Uri.parse('http://192.168.0.10:8787/');

  late http.Request sent;
  ApiClient clientWith(int status, Object? body) => ApiClient(
        client: MockClient((request) async {
          sent = request;
          return http.Response(body == null ? '' : jsonEncode(body), status);
        }),
        baseUri: base,
      );

  Map<String, Object?> sentBody() =>
      jsonDecode(sent.body) as Map<String, Object?>;

  Map<String, Object?> error(String code) => {
        'error': {'code': code, 'message': 'em inglês'},
      };

  test('Group lê membros, playlist e conteúdo nulo', () {
    final group = Group.fromJson(_groupJson);

    expect(group.id, 3);
    expect(group.deviceIds, ['a', 'b']);
    expect(group.content, isNull);
    expect(group.playlist?.name, 'Manhã');
    expect(group.contentLabel, 'Playlist: Manhã');
  });

  test('Schedule lê HH:MM em minutos e escreve de volta', () {
    final s = Schedule.fromJson(_scheduleJson);

    expect(s.groupId, 3);
    expect(s.deviceId, isNull);
    expect(s.days, {1, 2, 3, 4, 5});
    expect(s.startMinute, 660);
    expect(s.endMinute, 840);
    expect(s.toJson(), {
      'name': 'Almoço',
      'playlistId': 'p1',
      'groupId': 3,
      'days': [1, 2, 3, 4, 5],
      'start': '11:00',
      'end': '14:00',
      'priority': 10,
    });
  });

  test('listGroups e createGroup', () async {
    final groups = await clientWith(200, {
      'groups': [_groupJson],
    }).listGroups();
    expect(groups.single.name, 'Recepção');
    expect(sent.method, 'GET');
    expect(sent.url.path, '/api/v1/groups');

    await clientWith(201, _groupJson).createGroup('Recepção');
    expect(sent.method, 'POST');
    expect(sentBody(), {'name': 'Recepção'});
  });

  test('renameGroup, deleteGroup e setGroupMembers', () async {
    await clientWith(200, _groupJson).renameGroup(3, 'Hall');
    expect(sent.method, 'PATCH');
    expect(sent.url.path, '/api/v1/groups/3');
    expect(sentBody(), {'name': 'Hall'});

    await clientWith(204, null).deleteGroup(3);
    expect(sent.method, 'DELETE');
    expect(sent.url.path, '/api/v1/groups/3');

    await clientWith(200, _groupJson).setGroupMembers(3, ['a', 'b']);
    expect(sent.method, 'PUT');
    expect(sent.url.path, '/api/v1/groups/3/devices');
    expect(sentBody(), {
      'deviceIds': ['a', 'b'],
    });
  });

  test('setGroupContent usa o mesmo formato do conteúdo da TV', () async {
    final api = clientWith(200, _groupJson);

    await api.setGroupContent(3, playlistId: 'p1');
    expect(sent.url.path, '/api/v1/groups/3/content');
    expect(sentBody(), {'playlistId': 'p1'});

    await api.setGroupContent(3, mediaId: 'm1');
    expect(sentBody(), {'mediaId': 'm1'});

    await api.setGroupContent(3, url: 'https://example.local/x', name: 'X');
    expect(sentBody(), {'url': 'https://example.local/x', 'name': 'X'});

    await api.setGroupContent(3);
    expect(sentBody(), {'mediaId': null});
  });

  test('setDeviceGroup manda groupId, inclusive null', () async {
    final device = {
      'id': 'a',
      'name': 'TV',
      'online': false,
      'createdAt': '2026-10-01T10:00:00.000Z',
      'groupId': 3,
    };
    final updated = await clientWith(200, device).setDeviceGroup('a', 3);
    expect(sent.method, 'PATCH');
    expect(sent.url.path, '/api/v1/devices/a');
    expect(sentBody(), {'groupId': 3});
    expect(updated.groupId, 3);

    await clientWith(200, device).setDeviceGroup('a', null);
    expect(sentBody(), {'groupId': null});
  });

  test('listSchedules filtra por TV ou grupo', () async {
    final body = {
      'schedules': [_scheduleJson],
    };

    expect(
      (await clientWith(200, body).listSchedules(groupId: 3)).single.name,
      'Almoço',
    );
    expect(sent.url.path, '/api/v1/schedules');
    expect(sent.url.queryParameters, {'groupId': '3'});

    await clientWith(200, body).listSchedules(deviceId: 'a');
    expect(sent.url.queryParameters, {'deviceId': 'a'});

    await clientWith(200, body).listSchedules();
    expect(sent.url.hasQuery, isFalse);
  });

  test('createSchedule, updateSchedule e deleteSchedule', () async {
    final schedule = Schedule.fromJson(_scheduleJson);

    await clientWith(201, _scheduleJson).createSchedule(schedule);
    expect(sent.method, 'POST');
    expect(sent.url.path, '/api/v1/schedules');
    expect(sentBody()['start'], '11:00');
    expect(sentBody().containsKey('id'), isFalse);

    await clientWith(200, _scheduleJson).updateSchedule('s1', schedule);
    expect(sent.method, 'PATCH');
    expect(sent.url.path, '/api/v1/schedules/s1');

    await clientWith(204, null).deleteSchedule('s1');
    expect(sent.method, 'DELETE');
    expect(sent.url.path, '/api/v1/schedules/s1');
  });

  test('erros conhecidos viram mensagens em português', () async {
    const expected = {
      'name_taken': 'Esse nome já está em uso.',
      'invalid_days': 'Escolha ao menos um dia da semana.',
      'invalid_time': 'Horário inválido. Use HH:MM, de 00:00 a 23:59.',
      'invalid_priority': 'A prioridade deve ser um número de 0 a 100.',
      'unknown_playlist': 'A playlist não existe mais.',
    };
    for (final MapEntry(:key, :value) in expected.entries) {
      await expectLater(
        clientWith(400, error(key)).deleteSchedule('s1'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', key)
              .having((e) => e.message, 'message', value),
        ),
      );
    }
  });
}
