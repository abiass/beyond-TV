import 'dart:async';
import 'dart:io';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_tv/src/app.dart';
import 'package:beyond_tv/src/content/manifest_store.dart';
import 'package:beyond_tv/src/device/credentials.dart';
import 'package:beyond_tv/src/realtime/backoff.dart';
import 'package:beyond_tv/src/remote/app_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fake_socket.dart';
import '../support/fakes.dart';

const _saved = Credentials(
  deviceId: 'tv-1',
  deviceToken: 'segredo',
  server: pcSala,
);

void main() {
  late Directory mediaDir;
  late FakeConnector connector;
  late MemoryCredentialStore credentials;
  late MemoryManifestStore manifests;
  late FakePlayerLog playerLog;
  late List<http.Request> deletes;

  Future<void> open(
    WidgetTester tester, {
    bool paired = true,
    bool serverUp = true,
  }) async {
    useTvScreen(tester);
    connector = FakeConnector();
    credentials = MemoryCredentialStore(paired ? _saved : null);
    manifests = MemoryManifestStore();
    playerLog = FakePlayerLog();
    deletes = [];
    await tester.pumpWidget(
      TvApp(
        mediaRoot: () async => mediaDir,
        mediaClient: () => MockClient((_) => Completer<http.Response>().future),
        credentials: credentials,
        discovery: FakeDiscovery([pcSala]),
        api: fakeApi(
          onlineHosts: serverUp ? {'192.168.0.10'} : {},
          routes: {
            'DELETE /api/v1/device': (request) {
              deletes.add(request);
              return http.Response('', 204);
            },
          },
        ),
        connector: connector.call,
        backoffFactory: () => Backoff(initial: const Duration(hours: 1)),
        manifestStore: manifests,
        webPlayer: fakeWebPlayer(playerLog),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Future<void> openMenu(WidgetTester tester) async {
    for (final key in [
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowDown,
    ]) {
      await tester.sendKeyEvent(key);
    }
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  setUp(() {
    mediaDir = Directory.systemTemp.createTempSync('hidden_menu_media');
    AppLog.instance.clear();
  });

  tearDown(() => mediaDir.deleteSync(recursive: true));

  testWidgets('⬆ ⬆ ⬇ ⬇ abre e mostra as informações', (tester) async {
    File('${mediaDir.path}/${'a' * 64}').writeAsBytesSync(List.filled(2048, 1));
    AppLog.instance.add('linha de teste do log');
    await open(tester);
    expect(find.text('Menu da TV'), findsNothing);

    await openMenu(tester);
    await tester.pump();

    expect(find.text('Menu da TV'), findsOneWidget);
    expect(find.textContaining('Id da TV: tv-1'), findsOneWidget);
    expect(
      find.textContaining('Servidor: PC-SALA · 192.168.0.10:8787'),
      findsOneWidget,
    );
    expect(find.textContaining('Conexão: Conectada'), findsOneWidget);
    expect(find.textContaining('Versão do app: 0.1.0'), findsOneWidget);
    expect(find.textContaining('Revisão do manifesto: '), findsOneWidget);
    expect(find.textContaining('Cache: 1 arquivo · 2,0 KB'), findsOneWidget);
    expect(find.textContaining('linha de teste do log'), findsOneWidget);
    expect(find.textContaining('segredo'), findsNothing);
    await close(tester);
  });

  testWidgets('OK segurado por 2 s abre; soltar antes não', (tester) async {
    await open(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(seconds: 1));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Menu da TV'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Menu da TV'), findsOneWidget);

    // O repeat do OK que abriu o menu não aperta nenhum botão.
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(find.text('Menu da TV'), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(find.text('Menu da TV'), findsOneWidget);
    await close(tester);
  });

  testWidgets('Fechar e Voltar fecham', (tester) async {
    await open(tester);
    await openMenu(tester);
    expect(find.text('Menu da TV'), findsOneWidget);

    // D-pad: Recarregar -> Desparear -> Fechar.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(find.text('Menu da TV'), findsNothing);

    await openMenu(tester);
    expect(find.text('Menu da TV'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Menu da TV'), findsNothing);

    await openMenu(tester);
    // Voltar do controle chega como pop do sistema.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Menu da TV'), findsNothing);
    await close(tester);
  });

  testWidgets('Recarregar recarrega o item e fecha o menu', (tester) async {
    await open(tester);
    connector.last.serverSend(
      Envelope.create(
        MessageTypes.contentSync,
        payload: ContentManifest(
          items: [
            ContentItem(
              mediaId: 'm1',
              kind: MediaKinds.url,
              name: 'Site',
              url: 'https://example.local/a',
            ),
          ],
        ).toJson(),
      ),
    );
    await tester.pump();
    await tester.pump();
    await openMenu(tester);
    expect(
      find.textContaining('Item exibido: https://example.local/a'),
      findsOneWidget,
    );

    await tester.tap(find.text('Recarregar'));
    await tester.pump();

    expect(playerLog.reloads, 1);
    expect(find.text('Menu da TV'), findsNothing);
    await close(tester);
  });

  testWidgets('Desparear pede confirmação e Cancelar não faz nada', (
    tester,
  ) async {
    await open(tester);
    await openMenu(tester);

    await tester.tap(find.text('Desparear'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Desparear esta TV?'), findsOneWidget);
    expect(
      find.text('Ela volta para a tela de pareamento.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancelar'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Desparear esta TV?'), findsNothing);
    expect(find.text('Menu da TV'), findsOneWidget);
    expect(deletes, isEmpty);
    expect(credentials.saved, isNotNull);
    await close(tester);
  });

  for (final serverUp in [true, false]) {
    testWidgets(
      'Desparear confirmado ${serverUp ? 'chama a API' : 'com a API fora'} '
      'e volta ao pareamento',
      (tester) async {
        File('${mediaDir.path}/${'b' * 64}').writeAsStringSync('x');
        await open(tester, serverUp: serverUp);
        await openMenu(tester);

        await tester.tap(find.text('Desparear'));
        await tester.pump();
        await tester.pump();
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Desparear'),
          ),
        );
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        if (serverUp) {
          expect(deletes, hasLength(1));
          expect(deletes.single.headers['Authorization'], 'Bearer segredo');
          expect(deletes.single.url.path, '/api/v1/device');
        }
        expect(credentials.saved, isNull);
        expect(manifests.saved, isNull);
        expect(mediaDir.listSync(), isEmpty);
        expect(find.text('Escolha o servidor'), findsOneWidget);
        expect(find.text('Menu da TV'), findsNothing);
        await close(tester);
      },
    );
  }

  testWidgets('não abre durante o pareamento', (tester) async {
    await open(tester, paired: false);
    expect(find.text('Escolha o servidor'), findsOneWidget);

    await openMenu(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(seconds: 3));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(find.text('Menu da TV'), findsNothing);
    await close(tester);
  });
}
