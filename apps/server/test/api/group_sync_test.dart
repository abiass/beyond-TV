import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/realtime_support.dart';
import '../support/test_server.dart';

void main() {
  late TestServer server;
  late Map<String, String> admin;
  late ({String id, String token}) tv;
  late Inbox tvInbox;
  late int groupId;
  late String playlistId;

  Future<http.Response> send(String method, String path, [Object? body]) =>
      server.send(method, '/api/v1$path', json: body, headers: admin);

  Future<Map<Object?, Object?>> json(
    String method,
    String path, [
    Object? body,
  ]) async =>
      jsonBody(await send(method, path, body))! as Map<Object?, Object?>;

  setUp(() async {
    server = await TestServer.start();
    admin = await setupAdmin(server);
    tv = insertDevice(server);
    groupId = (await json('POST', '/groups', {'name': 'Salão'}))['id'] as int;
    final media =
        await json('POST', '/media', {
              'kind': 'url',
              'url': 'https://a.local/p',
              'name': 'P',
            })
            as Map;
    playlistId =
        (await json('POST', '/playlists', {'name': 'Almoço'}))['id'] as String;
    await send('PUT', '/playlists/$playlistId/items', {
      'items': [
        {'mediaId': media['id']},
      ],
    });
  });

  Future<Inbox> connect(({String id, String token}) device) async {
    final channel = await connectDevice(server, device.token);
    final inbox = Inbox(channel);
    sendHello(channel);
    return inbox;
  }

  Future<ContentManifest> nextSync(Inbox inbox) async =>
      ContentManifest.fromJson(
        (await inbox.nextOfType(MessageTypes.contentSync)).payload,
      );

  Future<void> expectNoSync(Inbox inbox) => expectLater(
    inbox.nextOfType(MessageTypes.contentSync),
    throwsA(isA<Exception>()),
  );

  Future<void> putGroupContent() =>
      send('PUT', '/groups/$groupId/content', {'url': 'https://a.local/grupo'});

  Future<void> join() => send('PUT', '/groups/$groupId/devices', {
    'deviceIds': [tv.id],
  });

  test('TV sem conteúdo próprio recebe o padrão do grupo ao entrar', () async {
    await putGroupContent();
    tvInbox = await connect(tv);
    expect((await nextSync(tvInbox)).items, isEmpty);

    await join();

    final manifest = await nextSync(tvInbox);
    expect(manifest.items.single.url, 'https://a.local/grupo');
  });

  test('o conteúdo da TV vence o do grupo', () async {
    await putGroupContent();
    await join();
    await send('PUT', '/devices/${tv.id}/content', {
      'url': 'https://a.local/tv',
    });

    tvInbox = await connect(tv);

    expect((await nextSync(tvInbox)).items.single.url, 'https://a.local/tv');
  });

  test(
    'mudar o conteúdo do grupo atualiza a TV e limpar volta ao vazio',
    () async {
      await join();
      tvInbox = await connect(tv);
      expect((await nextSync(tvInbox)).items, isEmpty);

      await putGroupContent();
      expect(
        (await nextSync(tvInbox)).items.single.url,
        'https://a.local/grupo',
      );

      await send('PUT', '/groups/$groupId/content', {'mediaId': null});
      expect((await nextSync(tvInbox)).items, isEmpty);
    },
  );

  test('sair do grupo tira o conteúdo herdado', () async {
    await putGroupContent();
    await join();
    tvInbox = await connect(tv);
    expect((await nextSync(tvInbox)).items, hasLength(1));

    await send('PATCH', '/devices/${tv.id}', {'groupId': null});

    expect((await nextSync(tvInbox)).items, isEmpty);
  });

  test('apagar o grupo manda o manifesto sem o conteúdo e a agenda', () async {
    await putGroupContent();
    await join();
    await send('POST', '/schedules', {
      'name': 'Almoço',
      'playlistId': playlistId,
      'groupId': groupId,
      'days': [1],
      'start': '11:00',
      'end': '14:00',
      'priority': 1,
    });
    tvInbox = await connect(tv);
    final before = await nextSync(tvInbox);
    expect(before.schedules, hasLength(1));

    await send('DELETE', '/groups/$groupId');

    final after = await nextSync(tvInbox);
    expect(after.items, isEmpty);
    expect(after.schedules, isEmpty);
  });

  test('TV em outro grupo não recebe nada', () async {
    final other = insertDevice(server, name: 'Outra');
    final otherGroup =
        (await json('POST', '/groups', {'name': 'Cozinha'}))['id'] as int;
    await send('PUT', '/groups/$otherGroup/devices', {
      'deviceIds': [other.id],
    });
    final otherInbox = await connect(other);
    expect((await nextSync(otherInbox)).items, isEmpty);

    await putGroupContent();
    await join();

    await expectNoSync(otherInbox);
  });

  group('agendamentos', () {
    Future<Map<Object?, Object?>> schedule([
      Map<String, Object?> override = const {},
    ]) => json('POST', '/schedules', {
      'name': 'Almoço',
      'playlistId': playlistId,
      'groupId': groupId,
      'days': [1, 2, 3, 4, 5],
      'start': '11:00',
      'end': '14:00',
      'priority': 10,
      ...override,
    });

    test('criar manda content.sync com schedules', () async {
      await join();
      tvInbox = await connect(tv);
      await nextSync(tvInbox);

      final created = await schedule();

      final manifest = await nextSync(tvInbox);
      final rule = manifest.schedules.single;
      expect(rule.id, created['id']);
      expect(rule.target, ScheduleTargets.group);
      expect(rule.days, {1, 2, 3, 4, 5});
      expect(rule.startMinute, 660);
      expect(rule.endMinute, 840);
      expect(rule.priority, 10);
      expect(rule.items.single.url, 'https://a.local/p');
      expect(manifest.items, isEmpty);
    });

    test('hello já traz a agenda, na ordem de precedência', () async {
      await join();
      final group = await schedule({'name': 'grupo', 'priority': 10});
      final own = await schedule({
        'name': 'tv',
        'groupId': null,
        'deviceId': tv.id,
        'priority': 10,
      });
      final top = await schedule({'name': 'topo', 'priority': 50});

      tvInbox = await connect(tv);

      final rules = (await nextSync(tvInbox)).schedules;
      expect(
        [for (final r in rules) r.id],
        [top['id'], own['id'], group['id']],
      );
      expect(rules[1].target, ScheduleTargets.device);
    });

    test('agendamento de grupo não chega à TV de fora do grupo', () async {
      tvInbox = await connect(tv);
      await nextSync(tvInbox);

      await schedule();

      await expectNoSync(tvInbox);
    });

    test('renomear o agendamento não manda content.sync', () async {
      await join();
      final created = await schedule();
      tvInbox = await connect(tv);
      await nextSync(tvInbox);

      await send('PATCH', '/schedules/${created['id']}', {'name': 'Outro'});

      await expectNoSync(tvInbox);
    });

    test(
      'mudar horário, apagar e esvaziar a playlist mandam content.sync',
      () async {
        await join();
        final created = await schedule();
        tvInbox = await connect(tv);
        final first = await nextSync(tvInbox);

        await send('PATCH', '/schedules/${created['id']}', {'end': '15:00'});
        final changed = await nextSync(tvInbox);
        expect(changed.revision, isNot(first.revision));
        expect(changed.schedules.single.endMinute, 900);

        await send('PUT', '/playlists/$playlistId/items', {'items': []});
        expect((await nextSync(tvInbox)).schedules.single.items, isEmpty);

        await send('DELETE', '/schedules/${created['id']}');
        expect((await nextSync(tvInbox)).schedules, isEmpty);
      },
    );

    test('apagar a playlist remove a regra do manifesto', () async {
      await join();
      await schedule();
      tvInbox = await connect(tv);
      expect((await nextSync(tvInbox)).schedules, hasLength(1));

      await send('DELETE', '/playlists/$playlistId');

      expect((await nextSync(tvInbox)).schedules, isEmpty);
    });
  });
}
