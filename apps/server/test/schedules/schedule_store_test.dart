import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_server/server.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../support/test_server.dart';

void main() {
  late Database db;
  late FakeClock clock;
  late ScheduleStore store;
  late String playlistId;
  late int groupId;

  setUp(() {
    db = openDatabase();
    clock = FakeClock();
    store = ScheduleStore(db, clock: clock.call);
    playlistId = PlaylistStore(db, MediaStore(db)).create('P').id;
    groupId = GroupStore(db).create('G').id;
    DeviceStore(db).create(
      id: 'tv1',
      name: 'TV',
      tokenHash: 'h1',
      info: const DeviceInfo(appVersion: '0.5.0'),
    );
  });
  tearDown(() => db.close());

  ScheduleData data({
    String name = 'Almoço',
    String? deviceId,
    int? groupId,
    Set<int> days = const {1, 2, 3, 4, 5},
    int start = 660,
    int end = 840,
    int priority = 10,
  }) => ScheduleData(
    name: name,
    playlistId: playlistId,
    deviceId: deviceId,
    groupId: groupId,
    days: days,
    startMinute: start,
    endMinute: end,
    priority: priority,
  );

  test('bitmask de dias: segunda é o bit 0 e domingo o bit 6', () {
    expect(daysToMask([1]), 1);
    expect(daysToMask([7]), 64);
    expect(daysToMask([1, 2, 3, 4, 5, 6, 7]), 127);
    expect(maskToDays(0x15), [1, 3, 5]);
  });

  test('cria e lê de volta com os dias, horários e alvo', () {
    final row = store.create(data(groupId: groupId, days: {7, 1}));

    final found = store.find(row.id)!;

    expect(found.data.days, {1, 7});
    expect(found.data.startMinute, 660);
    expect(found.data.endMinute, 840);
    expect(found.data.groupId, groupId);
    expect(found.data.deviceId, isNull);
    expect(found.target, ScheduleTargets.group);
    expect(found.createdAt, clock.now);
    expect(found.toJson()['days'], [1, 7]);
    expect(found.toJson()['start'], '11:00');
    expect(store.find('nada'), isNull);
  });

  test('update substitui os campos e delete apaga', () {
    final row = store.create(data(deviceId: 'tv1'));

    expect(
      store.update(row.id, data(name: 'Noite', groupId: groupId, priority: 50)),
      isTrue,
    );
    final found = store.find(row.id)!;
    expect(found.data.name, 'Noite');
    expect(found.data.deviceId, isNull);
    expect(found.data.priority, 50);
    expect(store.update('nada', data(deviceId: 'tv1')), isFalse);

    expect(store.delete(row.id), isTrue);
    expect(store.delete(row.id), isFalse);
  });

  test('list filtra pelo alvo direto', () {
    store.create(data(name: 'b', deviceId: 'tv1'));
    store.create(data(name: 'A', groupId: groupId));

    expect([for (final s in store.list()) s.data.name], ['A', 'b']);
    expect([for (final s in store.list(deviceId: 'tv1')) s.data.name], ['b']);
    expect([for (final s in store.list(groupId: groupId)) s.data.name], ['A']);
  });

  test('forDevice ordena por prioridade, TV antes de grupo e mais recente', () {
    final low = store.create(data(name: 'baixa', deviceId: 'tv1', priority: 1));
    clock.advance(const Duration(seconds: 1));
    final groupTie = store.create(
      data(name: 'grupo', groupId: groupId, priority: 10),
    );
    clock.advance(const Duration(seconds: 1));
    final deviceTie = store.create(
      data(name: 'tv', deviceId: 'tv1', priority: 10),
    );
    clock.advance(const Duration(seconds: 1));
    final deviceNewer = store.create(
      data(name: 'tv nova', deviceId: 'tv1', priority: 10),
    );
    clock.advance(const Duration(seconds: 1));
    final groupNewer = store.create(
      data(name: 'grupo novo', groupId: groupId, priority: 10),
    );
    final top = store.create(
      data(name: 'topo', groupId: groupId, priority: 90),
    );

    final ids = [for (final s in store.forDevice('tv1', groupId)) s.id];

    expect(ids, [
      top.id,
      deviceNewer.id,
      deviceTie.id,
      groupNewer.id,
      groupTie.id,
      low.id,
    ]);
  });

  test('forDevice ignora o grupo de outra TV e funciona sem grupo', () {
    final other = GroupStore(db).create('Outro').id;
    store.create(data(groupId: other));
    final own = store.create(data(deviceId: 'tv1'));

    expect([for (final s in store.forDevice('tv1', null)) s.id], [own.id]);
    expect(store.forDevice('tv1', groupId), hasLength(1));
    expect(store.forDevice('tv1', other), hasLength(2));
  });

  test('apagar playlist, TV e grupo apaga os agendamentos ligados', () {
    final byPlaylist = store.create(data(deviceId: 'tv1'));
    final otherPlaylist = PlaylistStore(db, MediaStore(db)).create('Q').id;
    store.create(
      ScheduleData(
        name: 'x',
        playlistId: otherPlaylist,
        groupId: groupId,
        days: const {1},
        startMinute: 0,
        endMinute: 60,
        priority: 0,
      ),
    );

    PlaylistStore(db, MediaStore(db)).delete(playlistId);
    expect(store.find(byPlaylist.id), isNull);
    expect(store.list(), hasLength(1));

    GroupStore(db).delete(groupId);
    expect(store.list(), isEmpty);

    final again = PlaylistStore(db, MediaStore(db)).create('R').id;
    store.create(
      ScheduleData(
        name: 'y',
        playlistId: again,
        deviceId: 'tv1',
        days: const {1},
        startMinute: 0,
        endMinute: 60,
        priority: 0,
      ),
    );
    DeviceStore(db).delete('tv1');
    expect(store.list(), isEmpty);
  });
}
