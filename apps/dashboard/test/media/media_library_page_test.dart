import 'dart:async';
import 'dart:typed_data';

import 'package:beyond_dashboard/src/api/api_client.dart';
import 'package:beyond_dashboard/src/media/file_picker.dart';
import 'package:beyond_dashboard/src/media/format_bytes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/library.dart';

void main() {
  late FakeApi api;
  late FakePicker picker;

  setUp(() {
    api = FakeApi(adminPassword: 'senha-forte-1', loggedIn: true)
      ..media.addAll(sampleMedia());
    picker = FakePicker();
  });

  Future<void> openLibrary(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(dashboardWith(api, picker: picker));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mídia'));
    await tester.pumpAndSettle();
  }

  PickedFile file(String name, String mime, int size) =>
      PickedFile(name: name, mime: mime, bytes: Uint8List(size));

  test('formata tamanhos e nomes', () {
    expect(formatBytes(500), '500 B');
    expect(formatBytes(183422), '179 KB');
    expect(formatBytes(13000000), '12,4 MB');
    expect(defaultMediaName('foto.final.PNG'), 'foto.final');
    expect(defaultMediaName('a' * 80 + '.png'), 'a' * 64);
    expect(defaultMediaName('.png'), '.png');
    expect(mimeFromFileName('x.JPG'), 'image/jpeg');
  });

  testWidgets('lista imagem, vídeo e site com tipo e tamanho', (tester) async {
    await openLibrary(tester);

    expect(find.text('Promoção'), findsOneWidget);
    expect(find.text('Imagem · 179 KB'), findsOneWidget);
    expect(find.text('Institucional'), findsOneWidget);
    expect(find.text('Vídeo · 12,4 MB'), findsOneWidget);
    expect(find.text('Painel'), findsOneWidget);
    expect(find.text('Site · https://example.local/painel'), findsOneWidget);
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
  });

  testWidgets('envia o arquivo escolhido com mime, bytes e nome',
      (tester) async {
    await openLibrary(tester);
    picker.next = file('Cartaz de verão.png', 'image/png', 1000);

    await tester.tap(find.text('Enviar arquivo'));
    await tester.pumpAndSettle();

    expect(picker.lastAccepted, contains('video/webm'));
    expect(picker.lastAccepted, contains('image/gif'));
    expect(api.uploads, hasLength(1));
    expect(api.uploads.single.mime, 'image/png');
    expect(api.uploads.single.bytes, hasLength(1000));
    expect(api.uploads.single.name, 'Cartaz de verão');
    expect(find.text('Arquivo enviado.'), findsOneWidget);
    expect(find.text('Cartaz de verão'), findsOneWidget);
  });

  testWidgets('cancelar o seletor não envia nada', (tester) async {
    await openLibrary(tester);

    await tester.tap(find.text('Enviar arquivo'));
    await tester.pumpAndSettle();

    expect(picker.calls, 1);
    expect(api.uploads, isEmpty);
  });

  testWidgets('tipo inválido mostra erro sem chamar a API', (tester) async {
    await openLibrary(tester);
    picker.next = file('x.pdf', 'application/pdf', 10);

    await tester.tap(find.text('Enviar arquivo'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tipo de arquivo não aceito'), findsOneWidget);
    expect(api.uploads, isEmpty);
  });

  testWidgets('imagem acima de 25 MiB mostra erro sem chamar a API',
      (tester) async {
    await openLibrary(tester);
    picker.next = file('grande.png', 'image/png', 25 * 1024 * 1024 + 1);

    await tester.tap(find.text('Enviar arquivo'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('O limite para imagem é 25,0 MB'),
      findsOneWidget,
    );
    expect(api.uploads, isEmpty);
  });

  testWidgets('sem MIME do navegador usa a extensão', (tester) async {
    await openLibrary(tester);
    picker.next = file('clipe.mp4', '', 10);

    await tester.tap(find.text('Enviar arquivo'));
    await tester.pumpAndSettle();

    expect(api.uploads.single.mime, 'video/mp4');
  });

  for (final (status, texto) in [
    (413, 'maior que o limite'),
    (415, 'não corresponde'),
  ]) {
    testWidgets('erro $status do servidor vira mensagem amigável',
        (tester) async {
      await openLibrary(tester);
      picker.next = file('a.png', 'image/png', 10);
      api.failure = ApiException('x', code: 'x', status: status);

      await tester.tap(find.text('Enviar arquivo'));
      await tester.pumpAndSettle();

      expect(find.textContaining(texto), findsOneWidget);
    });
  }

  testWidgets('durante o envio mostra progresso e bloqueia o botão',
      (tester) async {
    await openLibrary(tester);
    picker.next = file('a.png', 'image/png', 10);
    final gate = api.uploadGate = Completer<void>();

    await tester.tap(find.text('Enviar arquivo'));
    await tester.pump();
    // O seletor ainda não respondeu: botão bloqueado e barra visível.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Enviar arquivo'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );
    expect(button.onPressed, isNull);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('adiciona um site, validando o endereço', (tester) async {
    await openLibrary(tester);

    await tester.tap(find.text('Adicionar site'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Endereço do site'),
      'javascript:alert(1)',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Adicionar'));
    await tester.pumpAndSettle();
    expect(
      find.text('Use um link que comece com http:// ou https://.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Endereço do site'),
      'https://example.local/vendas',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Adicionar'));
    await tester.pumpAndSettle();

    expect(find.text('example.local'), findsOneWidget);
  });

  testWidgets('renomeia uma mídia', (tester) async {
    await openLibrary(tester);

    await tester.tap(find.byTooltip('Ações').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Renomear'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome'),
      'Oferta',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(api.mediaRenames, [('img', 'Oferta')]);
    expect(find.text('Oferta'), findsOneWidget);
    expect(find.text('Promoção'), findsNothing);
  });

  testWidgets('apagar pede confirmação e avisa das playlists e TVs',
      (tester) async {
    await openLibrary(tester);

    await tester.tap(find.byTooltip('Ações').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apagar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('playlists e das TVs'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(api.mediaDeleted, isEmpty);

    await tester.tap(find.byTooltip('Ações').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apagar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apagar'));
    await tester.pumpAndSettle();

    expect(api.mediaDeleted, ['img']);
    expect(find.text('Promoção'), findsNothing);
  });
}
