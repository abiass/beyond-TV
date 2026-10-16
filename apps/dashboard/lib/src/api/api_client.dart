import 'dart:convert';
import 'dart:typed_data';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:http/http.dart' as http;

import 'groups.dart';
import 'media.dart';
import 'playlists.dart';
import 'schedules.dart';

/// Erro devolvido pela API (ou falha de rede), com mensagem pronta para
/// exibir.
class ApiException implements Exception {
  const ApiException(this.message, {this.code, this.status});

  /// Mensagem em português.
  final String message;

  /// Código estável do erro (`error.code`), quando veio do servidor.
  final String? code;

  /// Status HTTP, ou `null` se o servidor não respondeu.
  final int? status;

  @override
  String toString() => 'ApiException($status, $code): $message';
}

/// Cliente da API REST do servidor Beyond TV.
///
/// O dashboard é servido pelo próprio servidor, então as chamadas vão para a
/// mesma origem da página e o cookie de sessão segue automaticamente.
class ApiClient {
  ApiClient({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? Uri.base;

  final http.Client _client;
  final Uri _baseUri;

  /// Origem do servidor (a da página do dashboard).
  Uri get baseUri => _baseUri;

  /// Indica se o administrador já foi criado.
  Future<bool> isConfigured() async =>
      (await _send('GET', '/api/v1/setup/status'))['configured'] == true;

  /// Cria o administrador e já abre a sessão. Devolve o nome do usuário.
  Future<String> setup({
    required String username,
    required String password,
  }) =>
      _sendCredentials('/api/v1/setup', username, password);

  /// Abre a sessão. Devolve o nome do usuário.
  Future<String> login({
    required String username,
    required String password,
  }) =>
      _sendCredentials('/api/v1/auth/login', username, password);

  /// Usuário da sessão atual, ou `null` se não houver sessão.
  Future<String?> currentUser() async {
    try {
      return (await _send('GET', '/api/v1/auth/session'))['username']!
          as String;
    } on ApiException catch (e) {
      if (e.status == 401) return null;
      rethrow;
    }
  }

  Future<void> logout() => _send('POST', '/api/v1/auth/logout');

  /// Gera um código de pareamento para a TV digitar.
  Future<PairingCode> createPairingCode() async =>
      PairingCode.fromJson(await _send('POST', '/api/v1/pairing-codes'));

  /// Situação do código [code]: se a TV já pareou, traz o nome dela.
  Future<PairingStatus> pairingStatus(String code) async =>
      PairingStatus.fromJson(
        await _send('GET', '/api/v1/pairing-codes/$code'),
      );

  /// TVs aguardando aprovação, da mais antiga para a mais nova.
  Future<List<PendingPairRequest>> listPairRequests() async {
    final json = await _send('GET', '/api/v1/pair-requests');
    final requests = json['requests'];
    if (requests is! List) return const [];
    return [
      for (final request in requests)
        if (request is Map<String, Object?>)
          PendingPairRequest.fromJson(request),
    ];
  }

  /// Aprova o pedido [id]: a TV é cadastrada e devolvida.
  Future<DeviceSummary> approvePairRequest(String id) async =>
      DeviceSummary.fromJson(
        await _send('POST', '/api/v1/pair-requests/$id/approve'),
      );

  Future<void> rejectPairRequest(String id) =>
      _send('POST', '/api/v1/pair-requests/$id/reject');

  /// TVs pareadas, da mais nova para a mais antiga.
  Future<List<DeviceSummary>> listDevices() async {
    final json = await _send('GET', '/api/v1/devices');
    final devices = json['devices'];
    if (devices is! List) return const [];
    return [
      for (final device in devices)
        if (device is Map<String, Object?>) DeviceSummary.fromJson(device),
    ];
  }

  /// Renomeia a TV [id]. Devolve a TV atualizada.
  Future<DeviceSummary> renameDevice(String id, String name) async =>
      DeviceSummary.fromJson(
        await _send('PATCH', '/api/v1/devices/$id', body: {'name': name}),
      );

  /// Remove a TV [id] (o servidor responde 204, sem corpo).
  Future<void> removeDevice(String id) =>
      _send('DELETE', '/api/v1/devices/$id');

  /// Mídias da biblioteca (sites, imagens e vídeos), da mais nova para a
  /// mais antiga.
  Future<List<Media>> listMedia() async {
    final json = await _send('GET', '/api/v1/media');
    final media = json['media'];
    if (media is! List) return const [];
    return [
      for (final item in media)
        if (item is Map<String, Object?>) Media.fromJson(item),
    ];
  }

  /// Endereço do arquivo de [mediaId], para pré-visualizar no painel (o
  /// cookie de sessão segue sozinho, pois é a mesma origem).
  Uri fileUrl(String mediaId) => _baseUri.resolve(mediaFilePath(mediaId));

  /// Salva um site na biblioteca. Sem [name], o servidor usa o host.
  Future<Media> createSite(String url, {String? name}) async => Media.fromJson(
        await _send(
          'POST',
          '/api/v1/media',
          body: {
            'kind': MediaKinds.url,
            'url': url,
            if (name != null) 'name': name,
          },
        ),
      );

  /// Envia um arquivo (corpo cru, `Content-Type` = [mime]). Se o servidor já
  /// tem o mesmo arquivo, devolve a mídia existente.
  Future<Media> uploadMedia(
    Uint8List bytes, {
    required String mime,
    String? name,
  }) async =>
      Media.fromJson(
        await _send(
          'POST',
          Uri(
            path: '/api/v1/media/files',
            queryParameters: name == null ? null : {'name': name},
          ).toString(),
          bytes: bytes,
          contentType: mime,
        ),
      );

  Future<Media> renameMedia(String id, String name) async => Media.fromJson(
        await _send('PATCH', '/api/v1/media/$id', body: {'name': name}),
      );

  /// Apaga a mídia (e a tira das playlists e das TVs).
  Future<void> deleteMedia(String id) => _send('DELETE', '/api/v1/media/$id');

  /// Playlists, por nome.
  Future<List<PlaylistSummary>> listPlaylists() async {
    final json = await _send('GET', '/api/v1/playlists');
    final playlists = json['playlists'];
    if (playlists is! List) return const [];
    return [
      for (final item in playlists)
        if (item is Map<String, Object?>) PlaylistSummary.fromJson(item),
    ];
  }

  Future<Playlist> createPlaylist(String name) async => Playlist.fromJson(
        await _send('POST', '/api/v1/playlists', body: {'name': name}),
      );

  Future<Playlist> getPlaylist(String id) async =>
      Playlist.fromJson(await _send('GET', '/api/v1/playlists/$id'));

  Future<Playlist> renamePlaylist(String id, String name) async =>
      Playlist.fromJson(
        await _send('PATCH', '/api/v1/playlists/$id', body: {'name': name}),
      );

  Future<void> deletePlaylist(String id) =>
      _send('DELETE', '/api/v1/playlists/$id');

  /// Substitui a lista inteira, na ordem dada. `null` = duração padrão.
  Future<Playlist> setPlaylistItems(
    String id,
    List<(String mediaId, int? durationSeconds)> items,
  ) async =>
      Playlist.fromJson(
        await _send(
          'PUT',
          '/api/v1/playlists/$id/items',
          body: {
            'items': [
              for (final (mediaId, seconds) in items)
                {
                  'mediaId': mediaId,
                  if (seconds != null) 'durationSeconds': seconds,
                },
            ],
          },
        ),
      );

  /// Manda a TV [id] exibir a playlist [playlistId]; `null` limpa.
  Future<DeviceSummary> setDevicePlaylist(
    String id,
    String? playlistId,
  ) async =>
      DeviceSummary.fromJson(
        await _send(
          'PUT',
          '/api/v1/devices/$id/content',
          body: {'playlistId': playlistId},
        ),
      );

  /// Manda a TV [id] exibir o site [url], com [name] opcional.
  Future<DeviceSummary> setDeviceContentUrl(
    String id,
    String url, {
    String? name,
  }) async =>
      DeviceSummary.fromJson(
        await _send(
          'PUT',
          '/api/v1/devices/$id/content',
          body: {'url': url, if (name != null) 'name': name},
        ),
      );

  /// Manda a TV [id] exibir a mídia [mediaId]; `null` limpa o conteúdo.
  Future<DeviceSummary> setDeviceMedia(String id, String? mediaId) async =>
      DeviceSummary.fromJson(
        await _send(
          'PUT',
          '/api/v1/devices/$id/content',
          body: {'mediaId': mediaId},
        ),
      );

  /// Grupos de TVs, por nome.
  Future<List<Group>> listGroups() async {
    final json = await _send('GET', '/api/v1/groups');
    final groups = json['groups'];
    if (groups is! List) return const [];
    return [
      for (final item in groups)
        if (item is Map<String, Object?>) Group.fromJson(item),
    ];
  }

  Future<Group> createGroup(String name) async => Group.fromJson(
        await _send('POST', '/api/v1/groups', body: {'name': name}),
      );

  Future<Group> renameGroup(int id, String name) async => Group.fromJson(
        await _send('PATCH', '/api/v1/groups/$id', body: {'name': name}),
      );

  /// Apaga o grupo: as TVs ficam sem grupo e os agendamentos dele somem.
  Future<void> deleteGroup(int id) => _send('DELETE', '/api/v1/groups/$id');

  /// Define os membros do grupo (as TVs fora da lista saem).
  Future<Group> setGroupMembers(int id, List<String> deviceIds) async =>
      Group.fromJson(
        await _send(
          'PUT',
          '/api/v1/groups/$id/devices',
          body: {'deviceIds': deviceIds},
        ),
      );

  /// Conteúdo padrão do grupo: informe um entre [mediaId], [playlistId] e
  /// [url] (com [name] opcional); sem nenhum, limpa.
  Future<Group> setGroupContent(
    int id, {
    String? mediaId,
    String? playlistId,
    String? url,
    String? name,
  }) async =>
      Group.fromJson(
        await _send(
          'PUT',
          '/api/v1/groups/$id/content',
          body: playlistId != null
              ? {'playlistId': playlistId}
              : url != null
                  ? {'url': url, if (name != null) 'name': name}
                  : {'mediaId': mediaId},
        ),
      );

  /// Põe a TV [deviceId] no grupo [groupId]; `null` tira do grupo.
  Future<DeviceSummary> setDeviceGroup(String deviceId, int? groupId) async =>
      DeviceSummary.fromJson(
        await _send(
          'PATCH',
          '/api/v1/devices/$deviceId',
          body: {'groupId': groupId},
        ),
      );

  /// Agendamentos, opcionalmente só os de uma TV ou de um grupo.
  Future<List<Schedule>> listSchedules({String? deviceId, int? groupId}) async {
    final query = {
      if (deviceId != null) 'deviceId': deviceId,
      if (groupId != null) 'groupId': '$groupId',
    };
    final path = Uri(
      path: '/api/v1/schedules',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
    final json = await _send('GET', path);
    final schedules = json['schedules'];
    if (schedules is! List) return const [];
    return [
      for (final item in schedules)
        if (item is Map<String, Object?>) Schedule.fromJson(item),
    ];
  }

  Future<Schedule> createSchedule(Schedule schedule) async => Schedule.fromJson(
        await _send('POST', '/api/v1/schedules', body: schedule.toJson()),
      );

  /// Atualiza o agendamento [id] com todos os campos de [schedule].
  Future<Schedule> updateSchedule(String id, Schedule schedule) async =>
      Schedule.fromJson(
        await _send(
          'PATCH',
          '/api/v1/schedules/$id',
          body: schedule.toJson(),
        ),
      );

  Future<void> deleteSchedule(String id) =>
      _send('DELETE', '/api/v1/schedules/$id');

  /// Envia um dos `DeviceCommands` para a TV [id] (o servidor responde 202).
  Future<void> sendCommand(String id, String type) =>
      _send('POST', '/api/v1/devices/$id/commands', body: {'type': type});

  /// Pede uma captura de tela da TV [id] (o servidor responde 202). Devolve
  /// o `requestId` do pedido. `409 device_offline` e `429
  /// too_many_requests` viram [ApiException] com mensagem em português.
  Future<String> requestScreenshot(String id) async {
    final json = await _send(
      'POST',
      '/api/v1/devices/$id/commands',
      body: {'type': DeviceCommands.screenshot},
    );
    return json['requestId'] as String? ?? '';
  }

  /// Abre o controle ao vivo da TV [id] (fica na auditoria).
  Future<void> startLiveControl(String id) =>
      _send('POST', '/api/v1/devices/$id/live');

  /// Pede um quadro do controle ao vivo; chega como `device.screenshot`.
  Future<void> requestLiveFrame(String id) =>
      _send('POST', '/api/v1/devices/$id/live/frame');

  /// Envia um toque, tecla, texto ou rolagem para o site aberto na TV.
  Future<void> sendRemoteInput(String id, RemoteInput input) =>
      _send('POST', '/api/v1/devices/$id/live/input', body: input.toJson());

  /// Endereço da última captura da TV [id]. [capturedAt] entra como
  /// parâmetro só para o navegador não reaproveitar a imagem anterior.
  Uri screenshotUrl(String id, {DateTime? capturedAt}) => _baseUri.resolve(
        Uri(
          path: '/api/v1/devices/$id/screenshot',
          queryParameters: capturedAt == null
              ? null
              : {'t': '${capturedAt.millisecondsSinceEpoch}'},
        ).toString(),
      );

  /// Momento da última captura da TV [id] (cabeçalho `X-Captured-At`), ou
  /// `null` se o servidor não tem nenhuma (404).
  Future<DateTime?> getScreenshotInfo(String id) async {
    final http.Response response;
    try {
      response = await _client.get(screenshotUrl(id));
    } on http.ClientException {
      return null;
    }
    if (response.statusCode != 200) return null;
    return DateTime.tryParse(response.headers['x-captured-at'] ?? '');
  }

  /// Log de auditoria, do mais novo para o mais antigo. [before] pagina pelo
  /// `id` da última linha já carregada.
  Future<List<AuditEntry>> listAudit({int limit = 100, int? before}) async {
    final path = Uri(
      path: '/api/v1/audit',
      queryParameters: {
        'limit': '$limit',
        if (before != null) 'before': '$before',
      },
    ).toString();
    final json = await _send('GET', path);
    final entries = json['entries'];
    if (entries is! List) return const [];
    return [
      for (final item in entries)
        if (item is Map<String, Object?>) AuditEntry.fromJson(item),
    ];
  }

  Future<String> _sendCredentials(
    String path,
    String username,
    String password,
  ) async {
    final body = {'username': username, 'password': password};
    final json = await _send('POST', path, body: body);
    return json['username']! as String;
  }

  Future<Map<String, Object?>> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    Uint8List? bytes,
    String? contentType,
  }) async {
    final request = http.Request(method, _baseUri.resolve(path));
    if (bytes != null) {
      request.headers['content-type'] = contentType!;
      request.bodyBytes = bytes;
    } else if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request));
    } on http.ClientException {
      throw const ApiException(
        'Não foi possível falar com o servidor. Verifique se ele está '
        'rodando.',
      );
    }

    final json = _decode(response.body);
    if (response.statusCode >= 400) {
      final error = json['error'];
      throw switch (error) {
        {'code': final String code, 'message': final String message} =>
          ApiException(
            _knownErrors[code] ?? message,
            code: code,
            status: response.statusCode,
          ),
        _ => ApiException(
            'Erro inesperado do servidor (${response.statusCode}).',
            status: response.statusCode,
          ),
      };
    }
    return json;
  }

  /// Mensagens fixas em português para erros de grupos e agenda.
  static const _knownErrors = {
    'name_taken': 'Esse nome já está em uso.',
    'invalid_days': 'Escolha ao menos um dia da semana.',
    'invalid_time': 'Horário inválido. Use HH:MM, de 00:00 a 23:59.',
    'invalid_priority': 'A prioridade deve ser um número de 0 a 100.',
    'device_offline': 'A TV está offline.',
    'too_many_requests': 'Aguarde alguns segundos para capturar de novo.',
    'unknown_playlist': 'A playlist não existe mais.',
  };

  static Map<String, Object?> _decode(String body) {
    if (body.isEmpty) return const {};
    try {
      final json = jsonDecode(body);
      return json is Map<String, Object?> ? json : const {};
    } on FormatException {
      return const {};
    }
  }
}

/// Situação de um código de pareamento.
enum PairingState { pending, paired, expired }

class PairingStatus {
  const PairingStatus(this.state, {this.deviceName});

  factory PairingStatus.fromJson(Map<String, Object?> json) => PairingStatus(
        PairingState.values.firstWhere(
          (state) => state.name == json['status'],
          orElse: () => PairingState.expired,
        ),
        deviceName: json['deviceName'] as String?,
      );

  final PairingState state;

  /// Nome dado à TV no pareamento (fabricante e modelo).
  final String? deviceName;
}
