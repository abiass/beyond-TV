import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:test/test.dart';

ContentItem _site(String name) => ContentItem(
      mediaId: name,
      kind: MediaKinds.url,
      name: name,
      url: 'https://example.local/$name',
    );

ScheduleRule _rule(
  String id, {
  Set<int> days = const {1, 2, 3, 4, 5, 6, 7},
  required String start,
  required String end,
  int priority = 0,
  String target = ScheduleTargets.device,
}) =>
    ScheduleRule(
      id: id,
      days: days,
      startMinute: parseClockTime(start)!,
      endMinute: parseClockTime(end)!,
      priority: priority,
      target: target,
      items: [_site(id)],
    );

// 2026-10-12 é uma segunda-feira.
DateTime _at(int day, String time) {
  final minutes = parseClockTime(time)!;
  return DateTime(2026, 10, 11 + day, minutes ~/ 60, minutes % 60);
}

void main() {
  group('horário', () {
    test('parseClockTime aceita HH:MM de 00:00 a 23:59', () {
      expect(parseClockTime('00:00'), 0);
      expect(parseClockTime('08:30'), 510);
      expect(parseClockTime('23:59'), 1439);
      for (final bad in ['24:00', '8:30', '08:60', '0830', '', '08:30:00']) {
        expect(parseClockTime(bad), isNull, reason: bad);
      }
    });

    test('formatClockTime é o inverso', () {
      for (final minutes in [0, 59, 510, 1439]) {
        expect(parseClockTime(formatClockTime(minutes)), minutes);
      }
    });
  });

  group('ScheduleRule.isActiveAt', () {
    test('faixa no mesmo dia inclui o início e exclui o fim', () {
      final rule =
          _rule('manha', days: {DateTime.monday}, start: '08:00', end: '12:00');

      expect(rule.isActiveAt(_at(1, '07:59')), isFalse);
      expect(rule.isActiveAt(_at(1, '08:00')), isTrue);
      expect(rule.isActiveAt(_at(1, '11:59')), isTrue);
      expect(rule.isActiveAt(_at(1, '12:00')), isFalse);
      expect(rule.isActiveAt(_at(2, '09:00')), isFalse, reason: 'terça');
    });

    test('faixa que vira a noite continua no dia seguinte', () {
      final rule =
          _rule('noite', days: {DateTime.friday}, start: '22:00', end: '02:00');

      expect(rule.isActiveAt(_at(5, '21:59')), isFalse);
      expect(rule.isActiveAt(_at(5, '23:30')), isTrue);
      expect(rule.isActiveAt(_at(6, '01:59')), isTrue, reason: 'sábado cedo');
      expect(rule.isActiveAt(_at(6, '02:00')), isFalse);
      expect(
        rule.isActiveAt(_at(6, '23:00')),
        isFalse,
        reason: 'sábado à noite',
      );
      expect(rule.isActiveAt(_at(5, '01:00')), isFalse, reason: 'sexta cedo');
    });

    test('domingo à noite continua na segunda', () {
      final rule =
          _rule('dom', days: {DateTime.sunday}, start: '23:00', end: '01:00');

      expect(rule.isActiveAt(_at(7, '23:10')), isTrue);
      expect(rule.isActiveAt(_at(8, '00:30')), isTrue);
      expect(rule.isActiveAt(_at(1, '01:00')), isFalse);
    });

    test('fim igual ao início cobre 24 horas', () {
      final rule =
          _rule('dia', days: {DateTime.monday}, start: '06:00', end: '06:00');

      expect(rule.isActiveAt(_at(1, '06:00')), isTrue);
      expect(rule.isActiveAt(_at(2, '05:59')), isTrue);
      expect(rule.isActiveAt(_at(2, '06:00')), isFalse);
    });
  });

  group('resolução no manifesto', () {
    final padrao = _site('padrao');

    test('sem agenda ativa vale o conteúdo padrão', () {
      final manifest = ContentManifest(
        items: [padrao],
        schedules: [_rule('manha', start: '08:00', end: '12:00')],
      );

      expect(manifest.itemsAt(_at(1, '13:00')), [padrao]);
      expect(manifest.activeScheduleAt(_at(1, '13:00')), isNull);
    });

    test('na sobreposição vale a primeira regra da lista', () {
      final manifest = ContentManifest(
        items: [padrao],
        schedules: [
          _rule('almoco', start: '11:00', end: '14:00', priority: 10),
          _rule('manha', start: '08:00', end: '12:00'),
        ],
      );

      expect(manifest.activeScheduleAt(_at(1, '09:00'))?.id, 'manha');
      expect(manifest.activeScheduleAt(_at(1, '11:30'))?.id, 'almoco');
      expect(manifest.activeScheduleAt(_at(1, '13:00'))?.id, 'almoco');
      expect(manifest.itemsAt(_at(1, '15:00')), [padrao]);
    });

    test('allItems junta o padrão e os itens de todas as regras', () {
      final manifest = ContentManifest(
        items: [padrao],
        schedules: [_rule('a', start: '08:00', end: '09:00')],
      );

      expect(manifest.allItems.map((i) => i.name), ['padrao', 'a']);
    });

    test('isEmpty considera os itens das regras', () {
      expect(ContentManifest(items: const []).isEmpty, isTrue);
      expect(
        ContentManifest(
          items: const [],
          schedules: [_rule('a', start: '08:00', end: '09:00')],
        ).isEmpty,
        isFalse,
      );
    });
  });

  group('nextChangeAfter', () {
    test('sem agenda não há próxima mudança', () {
      expect(
        ContentManifest(items: const []).nextChangeAfter(_at(1, '10:00')),
        isNull,
      );
    });

    test('devolve o próximo início ou fim, inclusive no dia seguinte', () {
      final manifest = ContentManifest(
        items: const [],
        schedules: [_rule('manha', start: '08:00', end: '12:00')],
      );

      expect(manifest.nextChangeAfter(_at(1, '07:00')), _at(1, '08:00'));
      expect(manifest.nextChangeAfter(_at(1, '08:00')), _at(1, '12:00'));
      expect(manifest.nextChangeAfter(_at(1, '13:00')), _at(2, '08:00'));
    });
  });

  group('JSON', () {
    test('regra faz ida e volta e ordena os dias', () {
      final rule = _rule(
        'noite',
        days: {DateTime.sunday, DateTime.monday},
        start: '22:00',
        end: '02:00',
        priority: 5,
        target: ScheduleTargets.group,
      );

      final json = rule.toJson();
      final decoded = ScheduleRule.fromJson(json);

      expect(json['days'], [1, 7]);
      expect(json['start'], '22:00');
      expect(decoded.days, {1, 7});
      expect(decoded.endMinute, rule.endMinute);
      expect(decoded.priority, 5);
      expect(decoded.target, ScheduleTargets.group);
      expect(decoded.items.single.name, 'noite');
    });

    test('horário inválido é erro de protocolo', () {
      final json = _rule('a', start: '08:00', end: '09:00').toJson()
        ..['start'] = '25:00';

      expect(
        () => ScheduleRule.fromJson(json),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('manifesto sem agenda mantém a revisão da fase 6', () {
      final items = [_site('a')];
      final semAgenda = ContentManifest(items: items);
      final comAgenda = ContentManifest(
        items: items,
        schedules: [_rule('b', start: '08:00', end: '09:00')],
      );

      expect(semAgenda.toJson().containsKey('schedules'), isFalse);
      expect(
        ContentManifest.fromJson(semAgenda.toJson()).revision,
        semAgenda.revision,
      );
      expect(comAgenda.revision, isNot(semAgenda.revision));
      final decoded = ContentManifest.fromJson(comAgenda.toJson());
      expect(decoded.revision, comAgenda.revision);
      expect(decoded.schedules.single.id, 'b');
    });
  });
}
