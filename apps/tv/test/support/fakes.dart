import 'dart:io';

import 'dart:convert';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:beyond_tv/src/device/credentials.dart';
import 'package:beyond_tv/src/player/web_player.dart';
import 'package:beyond_tv/src/device/device_info_source.dart';
import 'package:beyond_tv/src/server/discovery.dart';
import 'package:beyond_tv/src/server/server_address.dart';
import 'package:beyond_tv/src/server/tv_api.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Descoberta que devolve uma lista fixa.
class FakeDiscovery implements ServerDiscovery {
  FakeDiscovery([this.servers = const []]);

  List<ServerAddress> servers;
  int calls = 0;

  @override
  Future<List<ServerAddress>> discover() async {
    calls++;
    return servers;
  }
}

/// Servidor HTTP falso: responde `/health` nos [onlineHosts].
///
/// [routes] permite responder outras rotas (`'POST /api/v1/pair'`).
TvApi fakeApi({
  Set<String> onlineHosts = const {'192.168.0.10'},
  Map<String, http.Response Function(http.Request request)> routes = const {},
}) =>
    TvApi(
      client: MockClient((request) async {
        if (!onlineHosts.contains(request.url.host)) {
          throw http.ClientException('conexão recusada', request.url);
        }
        final route = routes['${request.method} ${request.url.path}'];
        if (route != null) return route(request);
        if (request.url.path == '/health') {
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        }
        return http.Response(
          jsonEncode({
            'error': {'code': 'not_found', 'message': 'Não encontrado.'},
          }),
          404,
        );
      }),
    );

const pcSala = ServerAddress(
  host: '192.168.0.10',
  name: 'PC-SALA',
  serverId: 'abc',
);

/// Dados fixos da TV.
class FakeDeviceInfo implements DeviceInfoSource {
  const FakeDeviceInfo();

  @override
  Future<DeviceInfo> read() async => const DeviceInfo(
        appVersion: appVersion,
        manufacturer: 'Acme',
        model: 'X1',
      );
}

/// Resposta JSON de erro no formato da API.
http.Response apiError(int status, String code, String message) =>
    http.Response(
      jsonEncode({
        'error': {'code': code, 'message': message},
      }),
      status,
    );

/// Simula a tela de uma Android TV 1080p (960×540 dp).
void useTvScreen(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1920, 1080)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

/// Armazenamento de credenciais em memória.
class MemoryCredentialStore implements CredentialStore {
  MemoryCredentialStore([this.saved]);

  Credentials? saved;

  @override
  Future<Credentials?> load() async => saved;

  @override
  Future<void> save(Credentials credentials) async => saved = credentials;

  @override
  Future<void> clear() async => saved = null;
}

/// Registro do player falso: quantos reloads e quais URLs foram abertas.
class FakePlayerLog {
  int reloads = 0;
}

class _FakePlayerController implements WebPlayerController {
  _FakePlayerController(this.log);

  final FakePlayerLog log;

  @override
  Future<void> reload() async => log.reloads++;
}

/// Player falso: mostra `WEB:<url>` e conta os reloads em [log].
WebPlayerBuilder fakeWebPlayer(FakePlayerLog log) => (context, url, onCreated) {
      onCreated(_FakePlayerController(log));
      return Text('WEB:$url');
    };

/// Pasta de mídia que nunca é criada: os testes de app não baixam nada.
Future<Directory> fakeMediaRoot() async =>
    Directory('${Directory.systemTemp.path}/beyond_tv_test_no_media');
