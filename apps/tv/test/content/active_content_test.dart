import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_tv/src/content/active_content.dart';
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

ContentItem _site(String id) => ContentItem(
      mediaId: id,
      kind: MediaKinds.url,
      name: id,
      url: 'https://example.local/$id',
    );

ScheduleRule _rule(
  String id,
  String start,
  String end, {
  Set<int> days = const {1, 2, 3, 4, 5, 6, 7},
  List<ContentItem>? items,
}) =>
    ScheduleRule(
      id: id,
      days: days,
      startMinute: parseClockTime(start)!,
      endMinute: parseClockTime(end)!,
      priority: 0,
      target: ScheduleTargets.device,
      items: items ?? [_site(id)],
    );

List<String> _ids(ActiveContent a) => [for (final i in a.items) i.mediaId];

// 2026-10-14 é uma quarta-feira.
final _start = DateTime(2026, 10, 14, 7, 59, 30);

void main() {
  test('sem agenda usa o padrão e não agenda timers', () {
    fakeAsync(
      (async) {
        final active = ActiveContent(now: () => clock.now());
        active.setManifest(ContentManifest(items: [_site('padrao')]));
        expect(_ids(active), ['padrao']);
        expect(async.pendingTimers, isEmpty);
        active.dispose();
      },
      initialTime: _start,
    );
  });

  test('troca exatamente no início e no fim da faixa', () {
    fakeAsync(
      (async) {
        final active = ActiveContent(now: () => clock.now());
        var notified = 0;
        active.addListener(() => notified++);
        active.setManifest(
          ContentManifest(
            items: [_site('padrao')],
            schedules: [_rule('manha', '08:00', '09:00')],
          ),
        );
        expect(_ids(active), ['padrao']);

        async.elapse(const Duration(seconds: 29));
        expect(_ids(active), ['padrao']);
        async.elapse(const Duration(seconds: 1));
        expect(_ids(active), ['manha']);
        expect(notified, 1);

        async.elapse(const Duration(minutes: 59, seconds: 59));
        expect(_ids(active), ['manha']);
        async.elapse(const Duration(seconds: 1));
        expect(_ids(active), ['padrao']);
        expect(notified, 2);
        active.dispose();
      },
      initialTime: _start,
    );
  });

  test('faixa que vira a noite', () {
    fakeAsync(
      (async) {
        final active = ActiveContent(now: () => clock.now());
        active.setManifest(
          ContentManifest(
            items: [_site('padrao')],
            schedules: [
              _rule('noite', '22:00', '06:00', days: {3}),
            ],
          ),
        );
        // Quarta 07:59:30: fora.
        expect(_ids(active), ['padrao']);
        async.elapse(const Duration(hours: 14, minutes: 0, seconds: 30));
        // Quarta 22:00.
        expect(_ids(active), ['noite']);
        async.elapse(const Duration(hours: 4));
        // Quinta 02:00: ainda vale (começou na quarta).
        expect(_ids(active), ['noite']);
        async.elapse(const Duration(hours: 4));
        // Quinta 06:00.
        expect(_ids(active), ['padrao']);
        active.dispose();
      },
      initialTime: _start,
    );
  });

  test('a reavaliação por minuto pega ajuste de relógio', () {
    fakeAsync(
      (async) {
        var offset = Duration.zero;
        final active = ActiveContent(now: () => clock.now().add(offset));
        var notified = 0;
        active.addListener(() => notified++);
        active.setManifest(
          ContentManifest(
            items: [_site('padrao')],
            schedules: [_rule('tarde', '15:00', '16:00')],
          ),
        );
        expect(_ids(active), ['padrao']);

        // O relógio da TV pula para 15:30 sem o timer de faixa disparar.
        offset = const Duration(hours: 7, minutes: 30);
        async.elapse(const Duration(seconds: 59));
        expect(_ids(active), ['padrao']);
        async.elapse(const Duration(seconds: 1));
        expect(_ids(active), ['tarde']);
        expect(notified, 1);
        active.dispose();
      },
      initialTime: _start,
    );
  });

  test('não notifica quando nada mudou', () {
    fakeAsync(
      (async) {
        final active = ActiveContent(now: () => clock.now());
        var notified = 0;
        active.addListener(() => notified++);
        active.setManifest(
          ContentManifest(
            items: [_site('padrao')],
            schedules: [_rule('tarde', '15:00', '16:00')],
          ),
        );
        final version = active.version;
        async.elapse(const Duration(minutes: 30));
        expect(notified, 0);
        expect(active.version, version);
        active.dispose();
      },
      initialTime: _start,
    );
  });

  test('manifesto novo reagenda', () {
    fakeAsync(
      (async) {
        final active = ActiveContent(now: () => clock.now());
        active.setManifest(
          ContentManifest(
            items: [_site('padrao')],
            schedules: [_rule('manha', '08:00', '09:00')],
          ),
        );
        final version = active.version;
        active.setManifest(
          ContentManifest(
            items: [_site('padrao')],
            schedules: [_rule('outra', '08:00', '08:30')],
          ),
        );
        expect(active.version, isNot(version));

        async.elapse(const Duration(seconds: 30));
        expect(_ids(active), ['outra']);
        async.elapse(const Duration(minutes: 30));
        expect(_ids(active), ['padrao']);

        // Sem agenda nenhum timer fica pendente.
        active.setManifest(ContentManifest(items: [_site('padrao')]));
        expect(async.pendingTimers, isEmpty);
        active.dispose();
      },
      initialTime: _start,
    );
  });

  test('dispose cancela os timers', () {
    fakeAsync(
      (async) {
        final active = ActiveContent(now: () => clock.now());
        active.setManifest(
          ContentManifest(
            items: [_site('padrao')],
            schedules: [_rule('manha', '08:00', '09:00')],
          ),
        );
        expect(async.pendingTimers, isNotEmpty);
        active.dispose();
        expect(async.pendingTimers, isEmpty);
      },
      initialTime: _start,
    );
  });
}
