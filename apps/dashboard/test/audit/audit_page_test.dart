import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';

AuditEntry entry(int id, {int status = 200, String? admin = 'admin'}) =>
    AuditEntry(
      id: id,
      at: DateTime.utc(2026, 10, 1, 12),
      method: 'POST',
      path: '/api/v1/groups',
      status: status,
      adminName: admin,
      ip: '192.168.0.10',
    );

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi(adminPassword: 'x', loggedIn: true));

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(dashboardWith(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Auditoria'));
    await tester.pumpAndSettle();
  }

  testWidgets('lista com admin, IP e status de erro em destaque',
      (tester) async {
    api.audit.addAll([entry(2, status: 409, admin: null), entry(1)]);
    await open(tester);

    expect(find.text('Criou grupo'), findsNWidgets(2));
    expect(find.textContaining('192.168.0.10'), findsNWidgets(2));
    expect(find.textContaining(' · — · '), findsOneWidget);
    expect(find.textContaining(' · admin · '), findsOneWidget);
    final error = tester.widget<Text>(find.text('409'));
    expect(error.style?.fontWeight, FontWeight.bold);
    expect(error.style?.color, isNotNull);
    expect(tester.widget<Text>(find.text('200')).style?.color, isNull);
    expect(find.text('Carregar mais'), findsNothing);
    expect(api.auditCalls, [(100, null)]);
  });

  testWidgets('Carregar mais usa o menor id e some no fim', (tester) async {
    api.audit.addAll([for (var i = 150; i >= 1; i--) entry(i)]);
    await open(tester);

    await tester.scrollUntilVisible(
      find.text('Carregar mais'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Carregar mais'), findsOneWidget);
    await tester.tap(find.text('Carregar mais'));
    await tester.pumpAndSettle();

    expect(api.auditCalls, [(100, null), (100, 51)]);
    expect(find.text('Carregar mais'), findsNothing);
  });
}
