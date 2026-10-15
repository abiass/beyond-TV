import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_tv/src/app.dart';
import 'package:beyond_tv/src/device/credentials.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';
import '../support/fakes.dart';

void main() {
  final credentials = Credentials.fromPairing(
    pcSala,
    const PairResponse(
      deviceId: 'tv1',
      deviceToken: 'segredo',
      serverId: 'abc',
    ),
  );

  group('SecureCredentialStore', () {
    const store = SecureCredentialStore();

    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('começa vazio', () async {
      expect(await store.load(), isNull);
    });

    test('salva, lê e apaga', () async {
      await store.save(credentials);

      final loaded = await store.load();
      expect(loaded?.deviceId, 'tv1');
      expect(loaded?.deviceToken, 'segredo');
      expect(loaded?.server, credentials.server);

      await store.clear();
      expect(await store.load(), isNull);
    });

    test('descarta dados corrompidos para parear de novo', () async {
      FlutterSecureStorage.setMockInitialValues({
        'beyond.credentials': '{"deviceId": 1}',
      });

      expect(await store.load(), isNull);
      expect(
        await const FlutterSecureStorage().read(key: 'beyond.credentials'),
        isNull,
      );
    });
  });

  test('toString não expõe o token', () {
    expect(credentials.toString(), isNot(contains('segredo')));
  });

  testWidgets('TV já pareada abre direto na tela de pareada', (tester) async {
    final discovery = FakeDiscovery([pcSala]);
    await tester.pumpWidget(
      TvApp(
        mediaRoot: fakeMediaRoot,
        credentials: MemoryCredentialStore(credentials),
        discovery: discovery,
        api: fakeApi(),
        connector: FakeConnector().call,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('TV pareada!'), findsOneWidget);
    expect(find.textContaining('PC-SALA'), findsOneWidget);
    expect(discovery.calls, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
