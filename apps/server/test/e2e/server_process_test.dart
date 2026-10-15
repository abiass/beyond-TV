@Tags(['e2e'])
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_server/server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _senha = 'senha-longa-de-teste';

/// Recebe mensagens JSON de um socket e permite esperar por um tipo.
class _Caixa {
  _Caixa(this.socket) {
    socket.listen((m) {
      final msg = jsonDecode(m as String) as Map<String, Object?>;
      tipos.add(msg['type']! as String);
      _controller.add(msg);
    }, onDone: () => _fechado.complete());
  }

  final WebSocket socket;
  final tipos = <String>[];
  final _controller = StreamController<Map<String, Object?>>.broadcast();
  final _fechado = Completer<void>();

  /// Próxima mensagem do [tipo], ignorando as demais.
  Future<Map<String, Object?>> next(String tipo) => _controller.stream
      .firstWhere((m) => m['type'] == tipo)
      .timeout(const Duration(seconds: 5));

  Future<int?> fechamento() async {
    await _fechado.future.timeout(const Duration(seconds: 5));
    return socket.closeCode;
  }

  void enviar(Envelope e) => socket.add(e.encode());
}

Future<int> _portaTcpLivre() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final porta = s.port;
  await s.close();
  return porta;
}

Future<int> _portaUdpLivre() async {
  final s = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final porta = s.port;
  s.close();
  return porta;
}

void main() {
  late Directory tmp;
  late Process processo;
  late int porta;
  late String origem;
  final log = StringBuffer();
  final sockets = <WebSocket>[];

  late String cookie;
  late String deviceId;
  late String deviceToken;
  late _Caixa admin;
  late _Caixa tv;

  Future<(int, Map<String, Object?>)> req(
    String metodo,
    String caminho, {
    Object? body,
    bool comCookie = true,
  }) async {
    final client = HttpClient();
    try {
      final r = await client.openUrl(metodo, Uri.parse('$origem$caminho'));
      r.headers.set('origin', origem);
      if (comCookie && cookie.isNotEmpty) r.headers.set('cookie', cookie);
      if (body != null) {
        r.headers.contentType = ContentType.json;
        r.write(jsonEncode(body));
      }
      final res = await r.close();
      final texto = await res.transform(utf8.decoder).join();
      if (res.headers.value('set-cookie') case final c?) {
        cookie = c.split(';').first;
      }
      final json = texto.isEmpty ? <String, Object?>{} : jsonDecode(texto);
      return (
        res.statusCode,
        json is Map<String, Object?> ? json : {'_': json},
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<WebSocket> conectar(
    String caminho,
    Map<String, Object> headers,
  ) async {
    final ws = await WebSocket.connect(
      'ws://127.0.0.1:$porta$caminho',
      headers: headers,
    );
    sockets.add(ws);
    return ws;
  }

  setUpAll(() async {
    cookie = '';
    tmp = await Directory.systemTemp.createTemp('beyond_e2e_');
    porta = await _portaTcpLivre();
    final udp = await _portaUdpLivre();
    origem = 'http://127.0.0.1:$porta';

    final dir = Directory.current.path;
    if (!File(p.join(dir, 'bin', 'server.dart')).existsSync()) {
      fail('Rode os testes a partir de apps/server (cwd atual: $dir).');
    }

    processo = await Process.start(Platform.resolvedExecutable, [
      'bin/server.dart',
      '--port',
      '$porta',
      '--discovery-port',
      '$udp',
      '--data-dir',
      tmp.path,
    ], workingDirectory: dir);

    final pronto = Completer<void>();
    void acumular(String linha) {
      log.writeln(linha);
      if (linha.contains('iniciado') && !pronto.isCompleted) pronto.complete();
    }

    for (final fluxo in [processo.stdout, processo.stderr]) {
      fluxo
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(acumular);
    }
    unawaited(
      processo.exitCode.then((code) {
        if (!pronto.isCompleted) {
          pronto.completeError(
            'Servidor saiu com $code antes de iniciar:\n$log',
          );
        }
      }),
    );

    await pronto.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw StateError('Servidor não iniciou em 60s:\n$log'),
    );
  });

  tearDownAll(() async {
    for (final s in sockets) {
      await s.close().timeout(const Duration(seconds: 2), onTimeout: () {});
    }
    processo.kill(ProcessSignal.sigint);
    await processo.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        processo.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  group('servidor como processo', () {
    test('setup do administrador e health', () async {
      final (status, _) = await req(
        'POST',
        '/api/v1/setup',
        body: {'username': 'admin', 'password': _senha},
        comCookie: false,
      );

      expect(status, inInclusiveRange(200, 299));
      expect(cookie, isNotEmpty);
      final (saude, _) = await req('GET', '/health');
      expect(saude, 200);
    });

    test('pareamento de uma TV', () async {
      final (_, codigo) = await req('POST', '/api/v1/pairing-codes');
      final (status, par) = await req(
        'POST',
        '/api/v1/pair',
        comCookie: false,
        body: {
          'code': codigo['code'],
          'deviceInfo': {'appVersion': '0.6.0', 'model': 'TV de teste'},
        },
      );

      expect(status, inInclusiveRange(200, 299));
      deviceId = par['deviceId']! as String;
      deviceToken = par['deviceToken']! as String;
      expect(deviceToken, isNotEmpty);
    });

    test('tempo real: hello, sync inicial e presença', () async {
      admin = _Caixa(
        await conectar(WsPaths.admin, {'cookie': cookie, 'origin': origem}),
      );
      tv = _Caixa(
        await conectar(WsPaths.device, {
          'authorization': 'Bearer $deviceToken',
        }),
      );
      final sync = tv.next(MessageTypes.contentSync);
      final online = admin.next(MessageTypes.deviceOnline);

      tv.enviar(
        Envelope.create(
          MessageTypes.hello,
          payload: {
            'deviceInfo': {'appVersion': '0.6.0'},
          },
        ),
      );

      final payload = (await sync)['payload']! as Map;
      expect(payload['items'], isEmpty);
      await online;
      final (_, lista) = await req('GET', '/api/v1/devices');
      final tvs = (lista['devices']! as List).cast<Map<String, Object?>>();
      expect(tvs.single['online'], isTrue);
    });

    test('renomear a TV', () async {
      final (status, corpo) = await req(
        'PATCH',
        '/api/v1/devices/$deviceId',
        body: {'name': 'Recepção'},
      );

      expect(status, 200);
      expect(corpo['name'], 'Recepção');
    });

    test('conteúdo: rejeita javascript: e entrega o site à TV', () async {
      final (ruim, erro) = await req(
        'PUT',
        '/api/v1/devices/$deviceId/content',
        body: {'url': 'javascript:alert(1)'},
      );
      expect(ruim, 400);
      expect((erro['error']! as Map)['code'], 'invalid_url');

      final sync = tv.next(MessageTypes.contentSync);
      final (status, _) = await req(
        'PUT',
        '/api/v1/devices/$deviceId/content',
        body: {'url': 'https://example.local/vendas', 'name': 'Vendas'},
      );

      expect(status, inInclusiveRange(200, 299));
      final msg = await sync;
      final payload = msg['payload']! as Map;
      expect(
        ((payload['items']! as List).first as Map)['url'],
        'https://example.local/vendas',
      );
      expect(payload['revision'], isNotEmpty);
      tv.enviar(Envelope.create(MessageTypes.ack, payload: {'ref': msg['id']}));

      final (_, midia) = await req('GET', '/api/v1/media');
      expect(midia['media'], hasLength(1));
    });

    test('comando identify chega à TV com o nome', () async {
      final identify = tv.next(MessageTypes.cmdIdentify);

      final (status, _) = await req(
        'POST',
        '/api/v1/devices/$deviceId/commands',
        body: {'type': 'identify'},
      );

      expect(status, inInclusiveRange(200, 299));
      final payload = (await identify)['payload']! as Map;
      expect(payload.values, contains('Recepção'));
    });

    test('token errado em /ws/device é recusado com 4401', () async {
      try {
        final ws = await conectar(WsPaths.device, {
          'authorization': 'Bearer errado',
        });
        expect(await _Caixa(ws).fechamento(), WsCloseCodes.unauthorized);
      } on WebSocketException catch (e) {
        expect(e.toString(), contains('401'));
      }
    });

    test('origin estranho em /ws/admin é recusado', () async {
      await expectLater(
        conectar(WsPaths.admin, {
          'cookie': cookie,
          'origin': 'http://evil.example',
        }),
        throwsA(
          isA<WebSocketException>().having(
            (e) => e.toString(),
            'texto',
            contains('403'),
          ),
        ),
      );
    });

    test('unpair fecha a TV com 4401 e remove o dispositivo', () async {
      final unpair = tv.next(MessageTypes.cmdUnpair);

      final (status, _) = await req(
        'POST',
        '/api/v1/devices/$deviceId/commands',
        body: {'type': 'unpair'},
      );

      expect(status, inInclusiveRange(200, 299));
      await unpair;
      expect(await tv.fechamento(), WsCloseCodes.unauthorized);
      final (_, lista) = await req('GET', '/api/v1/devices');
      expect(lista['devices'], isEmpty);
    });

    test('banco em arquivo e log sem segredos', () async {
      expect(File(p.join(tmp.path, databaseFileName)).existsSync(), isTrue);
      expect(admin.tipos, contains(MessageTypes.deviceOnline));

      final saida = log.toString();
      expect(saida, contains('iniciado'));
      expect(saida, isNot(contains(deviceToken)));
      expect(saida, isNot(contains(_senha)));
    });
  });
}
