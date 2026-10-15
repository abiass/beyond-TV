import 'dart:async';
import 'dart:typed_data';

import 'package:beyond_dashboard/src/api/api_client.dart';
import 'package:beyond_dashboard/src/api/groups.dart';
import 'package:beyond_dashboard/src/api/media.dart';
import 'package:beyond_dashboard/src/api/playlists.dart';
import 'package:beyond_dashboard/src/api/schedules.dart';
import 'package:beyond_dashboard/src/app.dart';
import 'package:beyond_dashboard/src/auth/auth_controller.dart';
import 'package:beyond_dashboard/src/media/file_picker.dart';
import 'package:beyond_dashboard/src/realtime/admin_events.dart';
import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fake_admin_socket.dart';

/// Servidor falso em memória, com as mesmas regras básicas do real.
class FakeApi implements ApiClient {
  FakeApi({this.adminPassword, this.loggedIn = false});

  /// Senha do administrador; `null` enquanto o setup não foi feito.
  String? adminPassword;
  bool loggedIn;

  /// Se preenchido, toda chamada falha com este erro.
  ApiException? failure;

  void _maybeFail() {
    if (failure case final failure?) throw failure;
  }

  @override
  Future<bool> isConfigured() async {
    _maybeFail();
    return adminPassword != null;
  }

  @override
  Future<String?> currentUser() async {
    _maybeFail();
    return loggedIn ? 'admin' : null;
  }

  @override
  Future<String> setup({
    required String username,
    required String password,
  }) async {
    _maybeFail();
    adminPassword = password;
    loggedIn = true;
    return username;
  }

  @override
  Future<String> login({
    required String username,
    required String password,
  }) async {
    _maybeFail();
    if (username != 'admin' || password != adminPassword) {
      throw const ApiException(
        'Usuário ou senha incorretos.',
        code: 'invalid_login',
        status: 401,
      );
    }
    loggedIn = true;
    return username;
  }

  @override
  Future<void> logout() async => loggedIn = false;

  /// Códigos gerados, em ordem.
  final codes = <String>[];

  /// Situação que [pairingStatus] devolve.
  PairingStatus status = const PairingStatus(PairingState.pending);
  int statusCalls = 0;

  @override
  Future<PairingCode> createPairingCode() async {
    _maybeFail();
    final code = 'K7M4Q${codes.length + 2}';
    codes.add(code);
    return PairingCode(
      code: code,
      expiresAt: DateTime.now().add(pairingCodeTtl),
    );
  }

  /// TVs que o servidor falso conhece.
  final devices = <DeviceSummary>[];

  @override
  Uri get baseUri => Uri.parse('http://localhost:8080/');

  @override
  Future<List<DeviceSummary>> listDevices() async {
    _maybeFail();
    return [...devices];
  }

  @override
  Future<DeviceSummary> renameDevice(String id, String name) async {
    _maybeFail();
    final i = devices.indexWhere((d) => d.id == id);
    return devices[i] = devices[i].copyWith(name: name);
  }

  @override
  Future<void> removeDevice(String id) async {
    _maybeFail();
    devices.removeWhere((d) => d.id == id);
  }

  /// Pedidos de aprovação pendentes.
  final pairRequests = <PendingPairRequest>[];

  /// Pedidos aprovados e recusados, em ordem.
  final approved = <String>[];
  final rejected = <String>[];

  @override
  Future<List<PendingPairRequest>> listPairRequests() async {
    _maybeFail();
    return [...pairRequests];
  }

  @override
  Future<DeviceSummary> approvePairRequest(String id) async {
    _maybeFail();
    final request = pairRequests.firstWhere(
      (r) => r.id == id,
      orElse: () => throw const ApiException(
        'Pedido não encontrado.',
        code: 'not_found',
        status: 404,
      ),
    );
    pairRequests.remove(request);
    approved.add(id);
    final device = DeviceSummary(
      id: 'tv-$id',
      name: request.deviceInfo.suggestedName,
      online: false,
      createdAt: DateTime.utc(2026, 10, 16),
      info: request.deviceInfo,
    );
    devices.insert(0, device);
    return device;
  }

  @override
  Future<void> rejectPairRequest(String id) async {
    _maybeFail();
    pairRequests.removeWhere((r) => r.id == id);
    rejected.add(id);
  }

  /// Sites salvos que [listMedia] devolve.
  final media = <Media>[];

  /// Comandos recebidos, como `(id, tipo)`.
  final commands = <(String, String)>[];

  /// Quantas vezes [setDeviceContentUrl] foi chamado.
  int setUrlCalls = 0;

  DeviceSummary _withContent(
    String id,
    ContentItem? content, {
    PlaylistRef? playlist,
  }) {
    final i = devices.indexWhere((d) => d.id == id);
    if (i < 0) {
      throw const ApiException(
        'TV não encontrada.',
        code: 'not_found',
        status: 404,
      );
    }
    final d = devices[i];
    return devices[i] = DeviceSummary(
      id: d.id,
      name: d.name,
      online: d.online,
      createdAt: d.createdAt,
      info: d.info,
      groupId: d.groupId,
      lastSeenAt: d.lastSeenAt,
      currentItem: d.currentItem,
      content: content,
      playlist: playlist,
    );
  }

  @override
  Future<List<Media>> listMedia() async {
    _maybeFail();
    return [...media];
  }

  @override
  Future<DeviceSummary> setDeviceContentUrl(
    String id,
    String url, {
    String? name,
  }) async {
    _maybeFail();
    setUrlCalls++;
    if (!isSafeContentUrl(url)) {
      throw const ApiException(
        'Endereço inválido.',
        code: 'invalid_url',
        status: 400,
      );
    }
    final label = name == null || name.trim().isEmpty ? url : name.trim();
    return _withContent(
      id,
      ContentItem(
        mediaId: 'm${media.length + 1}',
        kind: MediaKinds.url,
        name: label,
        url: url,
      ),
    );
  }

  @override
  Future<DeviceSummary> setDeviceMedia(String id, String? mediaId) async {
    _maybeFail();
    if (mediaId == null) return _withContent(id, null);
    final m = media.firstWhere((m) => m.id == mediaId);
    return _withContent(
      id,
      ContentItem(mediaId: m.id, kind: m.kind, name: m.name, url: m.url),
    );
  }

  /// Playlists que o servidor falso conhece, com os itens.
  final playlists = <Playlist>[];

  /// Chamadas de [setDevicePlaylist], como `(deviceId, playlistId)`.
  final playlistAssignments = <(String, String?)>[];

  /// Chamadas de [setPlaylistItems], como `(playlistId, itens)`.
  final savedItems = <(String, List<(String, int?)>)>[];

  /// Se preenchido, [uploadMedia] espera até ser completado.
  Completer<void>? uploadGate;

  /// Envios recebidos por [uploadMedia].
  final uploads = <({Uint8List bytes, String mime, String? name})>[];

  /// Renomeações e remoções de mídia, em ordem.
  final mediaRenames = <(String, String)>[];
  final mediaDeleted = <String>[];

  int _seq = 0;

  @override
  Uri fileUrl(String mediaId) => baseUri.resolve(mediaFilePath(mediaId));

  @override
  Future<Media> createSite(String url, {String? name}) async {
    _maybeFail();
    if (!isSafeContentUrl(url)) {
      throw const ApiException(
        'Endereço inválido.',
        code: 'invalid_url',
        status: 400,
      );
    }
    final m = Media(
      id: 's${++_seq}',
      kind: MediaKinds.url,
      name: name ?? Uri.parse(url).host,
      url: url,
      createdAt: DateTime.utc(2026, 10, 2),
    );
    media.insert(0, m);
    return m;
  }

  @override
  Future<Media> uploadMedia(
    Uint8List bytes, {
    required String mime,
    String? name,
  }) async {
    _maybeFail();
    await uploadGate?.future;
    uploads.add((bytes: bytes, mime: mime, name: name));
    final kind = mediaKindForMime(mime)!;
    final m = Media(
      id: 'u${++_seq}',
      kind: kind,
      name: name ?? (kind == MediaKinds.video ? 'Vídeo' : 'Imagem'),
      sha256: 'a' * 64,
      sizeBytes: bytes.length,
      mime: mime,
      createdAt: DateTime.utc(2026, 10, 2),
    );
    media.insert(0, m);
    return m;
  }

  @override
  Future<Media> renameMedia(String id, String name) async {
    _maybeFail();
    mediaRenames.add((id, name));
    final i = media.indexWhere((m) => m.id == id);
    final old = media[i];
    return media[i] = Media(
      id: old.id,
      kind: old.kind,
      name: name,
      url: old.url,
      sha256: old.sha256,
      sizeBytes: old.sizeBytes,
      mime: old.mime,
      createdAt: old.createdAt,
    );
  }

  @override
  Future<void> deleteMedia(String id) async {
    _maybeFail();
    mediaDeleted.add(id);
    media.removeWhere((m) => m.id == id);
  }

  @override
  Future<List<PlaylistSummary>> listPlaylists() async {
    _maybeFail();
    return [for (final p in playlists) p.summary];
  }

  @override
  Future<Playlist> createPlaylist(String name) async {
    _maybeFail();
    final p = Playlist(
      id: 'p${++_seq}',
      name: name,
      createdAt: DateTime.utc(2026, 10, 2),
    );
    playlists.add(p);
    return p;
  }

  int _playlistIndex(String id) {
    final i = playlists.indexWhere((p) => p.id == id);
    if (i < 0) {
      throw const ApiException(
        'Playlist não encontrada.',
        code: 'not_found',
        status: 404,
      );
    }
    return i;
  }

  @override
  Future<Playlist> getPlaylist(String id) async {
    _maybeFail();
    return playlists[_playlistIndex(id)];
  }

  @override
  Future<Playlist> renamePlaylist(String id, String name) async {
    _maybeFail();
    final i = _playlistIndex(id);
    final p = playlists[i];
    return playlists[i] = Playlist(
      id: p.id,
      name: name,
      createdAt: p.createdAt,
      items: p.items,
    );
  }

  @override
  Future<void> deletePlaylist(String id) async {
    _maybeFail();
    playlists.removeAt(_playlistIndex(id));
  }

  @override
  Future<Playlist> setPlaylistItems(
    String id,
    List<(String, int?)> items,
  ) async {
    _maybeFail();
    final i = _playlistIndex(id);
    savedItems.add((id, items));
    final p = playlists[i];
    return playlists[i] = Playlist(
      id: p.id,
      name: p.name,
      createdAt: p.createdAt,
      items: [
        for (final (mediaId, seconds) in items)
          PlaylistEntry(
            media: media.firstWhere((m) => m.id == mediaId),
            durationSeconds: seconds,
          ),
      ],
    );
  }

  @override
  Future<DeviceSummary> setDevicePlaylist(String id, String? playlistId) async {
    _maybeFail();
    playlistAssignments.add((id, playlistId));
    if (playlistId == null) return _withContent(id, null);
    final p = playlists[_playlistIndex(playlistId)];
    return _withContent(
      id,
      null,
      playlist: PlaylistRef(id: p.id, name: p.name),
    );
  }

  /// Grupos que o servidor falso conhece.
  final groups = <Group>[];

  /// Agendamentos que o servidor falso conhece.
  final schedules = <Schedule>[];

  /// Chamadas de [setGroupMembers], como `(groupId, deviceIds)`.
  final memberCalls = <(int, List<String>)>[];

  /// Chamadas de [setGroupContent], como `(groupId, corpo)`.
  final groupContentCalls = <(int, Map<String, String?>)>[];

  /// Chamadas de [setDeviceGroup], como `(deviceId, groupId)`.
  final deviceGroupCalls = <(String, int?)>[];

  /// Agendamentos enviados a [createSchedule] e [updateSchedule].
  final scheduleCreated = <Map<String, Object?>>[];
  final scheduleUpdated = <(String, Map<String, Object?>)>[];
  final scheduleDeleted = <String>[];

  int _groupSeq = 0;

  int _groupIndex(int id) {
    final i = groups.indexWhere((g) => g.id == id);
    if (i < 0) {
      throw const ApiException(
        'Grupo não encontrado.',
        code: 'not_found',
        status: 404,
      );
    }
    return i;
  }

  void _checkGroupName(String name, {int? except}) {
    if (groups.any(
      (g) => g.id != except && g.name.toLowerCase() == name.toLowerCase(),
    )) {
      throw const ApiException(
        'Esse nome já está em uso.',
        code: 'name_taken',
        status: 409,
      );
    }
  }

  Group _withGroup(
    Group g, {
    String? name,
    List<String>? deviceIds,
    ContentItem? content,
    PlaylistRef? playlist,
    bool setContent = false,
  }) =>
      Group(
        id: g.id,
        name: name ?? g.name,
        createdAt: g.createdAt,
        deviceIds: deviceIds ?? g.deviceIds,
        content: setContent ? content : g.content,
        playlist: setContent ? playlist : g.playlist,
      );

  @override
  Future<List<Group>> listGroups() async {
    _maybeFail();
    return [...groups]..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<Group> createGroup(String name) async {
    _maybeFail();
    _checkGroupName(name);
    final g = Group(
      id: ++_groupSeq + 100,
      name: name,
      createdAt: DateTime.utc(2026, 10, 2),
    );
    groups.add(g);
    return g;
  }

  @override
  Future<Group> renameGroup(int id, String name) async {
    _maybeFail();
    final i = _groupIndex(id);
    _checkGroupName(name, except: id);
    return groups[i] = _withGroup(groups[i], name: name);
  }

  @override
  Future<void> deleteGroup(int id) async {
    _maybeFail();
    groups.removeAt(_groupIndex(id));
    schedules.removeWhere((s) => s.groupId == id);
  }

  @override
  Future<Group> setGroupMembers(int id, List<String> deviceIds) async {
    _maybeFail();
    memberCalls.add((id, deviceIds));
    final i = _groupIndex(id);
    for (var j = 0; j < groups.length; j++) {
      groups[j] = _withGroup(
        groups[j],
        deviceIds: j == i
            ? deviceIds
            : [
                for (final d in groups[j].deviceIds)
                  if (!deviceIds.contains(d)) d,
              ],
      );
    }
    for (var j = 0; j < devices.length; j++) {
      final d = devices[j];
      final inGroup = deviceIds.contains(d.id);
      if (inGroup || d.groupId == id) {
        devices[j] = _withGroupId(d, inGroup ? id : null);
      }
    }
    return groups[i];
  }

  DeviceSummary _withGroupId(DeviceSummary d, int? groupId) => DeviceSummary(
        id: d.id,
        name: d.name,
        online: d.online,
        createdAt: d.createdAt,
        info: d.info,
        groupId: groupId,
        lastSeenAt: d.lastSeenAt,
        currentItem: d.currentItem,
        content: d.content,
        playlist: d.playlist,
      );

  @override
  Future<Group> setGroupContent(
    int id, {
    String? mediaId,
    String? playlistId,
    String? url,
    String? name,
  }) async {
    _maybeFail();
    groupContentCalls.add(
      (
        id,
        {
          if (mediaId != null) 'mediaId': mediaId,
          if (playlistId != null) 'playlistId': playlistId,
          if (url != null) 'url': url,
          if (name != null) 'name': name,
        },
      ),
    );
    final i = _groupIndex(id);
    if (playlistId != null) {
      final p = playlists[_playlistIndex(playlistId)];
      return groups[i] = _withGroup(
        groups[i],
        playlist: PlaylistRef(id: p.id, name: p.name),
        setContent: true,
      );
    }
    if (url != null) {
      return groups[i] = _withGroup(
        groups[i],
        content: ContentItem(
          mediaId: 'm-url',
          kind: MediaKinds.url,
          name: name ?? url,
          url: url,
        ),
        setContent: true,
      );
    }
    final m = mediaId == null ? null : media.firstWhere((m) => m.id == mediaId);
    return groups[i] = _withGroup(
      groups[i],
      content: m == null
          ? null
          : ContentItem(mediaId: m.id, kind: m.kind, name: m.name, url: m.url),
      setContent: true,
    );
  }

  @override
  Future<DeviceSummary> setDeviceGroup(String deviceId, int? groupId) async {
    _maybeFail();
    deviceGroupCalls.add((deviceId, groupId));
    final i = devices.indexWhere((d) => d.id == deviceId);
    return devices[i] = _withGroupId(devices[i], groupId);
  }

  @override
  Future<List<Schedule>> listSchedules({String? deviceId, int? groupId}) async {
    _maybeFail();
    return [
      for (final s in schedules)
        if ((deviceId == null || s.deviceId == deviceId) &&
            (groupId == null || s.groupId == groupId))
          s,
    ];
  }

  @override
  Future<Schedule> createSchedule(Schedule schedule) async {
    _maybeFail();
    scheduleCreated.add(schedule.toJson());
    final created = Schedule(
      id: 'sc${++_seq}',
      name: schedule.name,
      playlistId: schedule.playlistId,
      deviceId: schedule.deviceId,
      groupId: schedule.groupId,
      days: schedule.days,
      startMinute: schedule.startMinute,
      endMinute: schedule.endMinute,
      priority: schedule.priority,
      createdAt: DateTime.utc(2026, 10, 2).add(Duration(minutes: _seq)),
    );
    schedules.add(created);
    return created;
  }

  @override
  Future<Schedule> updateSchedule(String id, Schedule schedule) async {
    _maybeFail();
    scheduleUpdated.add((id, schedule.toJson()));
    final i = schedules.indexWhere((s) => s.id == id);
    final old = schedules[i];
    return schedules[i] = Schedule(
      id: id,
      name: schedule.name,
      playlistId: schedule.playlistId,
      deviceId: old.deviceId,
      groupId: old.groupId,
      days: schedule.days,
      startMinute: schedule.startMinute,
      endMinute: schedule.endMinute,
      priority: schedule.priority,
      createdAt: old.createdAt,
    );
  }

  @override
  Future<void> deleteSchedule(String id) async {
    _maybeFail();
    scheduleDeleted.add(id);
    schedules.removeWhere((s) => s.id == id);
  }

  @override
  Future<void> sendCommand(String id, String type) async {
    _maybeFail();
    final device = devices.firstWhere((d) => d.id == id);
    if (type != DeviceCommands.unpair && !device.online) {
      throw const ApiException(
        'A TV está offline.',
        code: 'device_offline',
        status: 409,
      );
    }
    commands.add((id, type));
    if (type == DeviceCommands.unpair) devices.remove(device);
  }

  /// Pedidos de captura, como ids de TV.
  final screenshotRequests = <String>[];

  /// Erro que [requestScreenshot] devolve, se preenchido.
  ApiException? screenshotError;

  /// Última captura de cada TV, como `id -> momento`.
  final screenshotAt = <String, DateTime>{};

  @override
  Future<String> requestScreenshot(String id) async {
    _maybeFail();
    if (screenshotError case final error?) throw error;
    screenshotRequests.add(id);
    return 'req-${screenshotRequests.length}';
  }

  @override
  Uri screenshotUrl(String id, {DateTime? capturedAt}) =>
      ApiClient(baseUri: baseUri).screenshotUrl(id, capturedAt: capturedAt);

  @override
  Future<DateTime?> getScreenshotInfo(String id) async => screenshotAt[id];

  /// TVs em que o controle ao vivo foi aberto.
  final liveStarted = <String>[];
  int liveFrames = 0;

  /// Entradas do controle remoto, em ordem.
  final inputs = <RemoteInput>[];

  /// Erro que os métodos do controle ao vivo devolvem, se preenchido.
  ApiException? liveError;

  @override
  Future<void> startLiveControl(String id) async {
    _maybeFail();
    if (liveError case final error?) throw error;
    liveStarted.add(id);
  }

  @override
  Future<void> requestLiveFrame(String id) async {
    _maybeFail();
    if (liveError case final error?) throw error;
    liveFrames++;
  }

  @override
  Future<void> sendRemoteInput(String id, RemoteInput input) async {
    _maybeFail();
    if (liveError case final error?) throw error;
    inputs.add(input);
  }

  /// Linhas de auditoria, da mais nova para a mais antiga.
  final audit = <AuditEntry>[];

  /// Chamadas de [listAudit], como `(limit, before)`.
  final auditCalls = <(int, int?)>[];

  @override
  Future<List<AuditEntry>> listAudit({int limit = 100, int? before}) async {
    _maybeFail();
    auditCalls.add((limit, before));
    return [
      for (final e in audit)
        if (before == null || e.id < before) e,
    ].take(limit).toList();
  }

  @override
  Future<PairingStatus> pairingStatus(String code) async {
    _maybeFail();
    statusCalls++;
    return status;
  }
}

/// O dashboard completo usando [api] e o canal ao vivo falso [socket].
Widget dashboardWith(
  FakeApi api, {
  FakeAdminSocket? socket,
  FilePicker? picker,
}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      if (picker != null) filePickerProvider.overrideWithValue(picker),
      // Sem [socket], cada reconexão (ex.: ao trocar de tela) ganha um novo.
      adminSocketConnectorProvider
          .overrideWithValue((_) => socket ?? FakeAdminSocket()),
    ],
    child: const DashboardApp(),
  );
}

/// Seletor de arquivos falso: devolve [next] (ou `null`, como cancelar).
class FakePicker implements FilePicker {
  PickedFile? next;
  int calls = 0;
  List<String>? lastAccepted;

  @override
  Future<PickedFile?> pick({required List<String> acceptedMimes}) async {
    calls++;
    lastAccepted = acceptedMimes;
    return next;
  }
}
