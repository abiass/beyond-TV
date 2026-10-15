import 'dart:async';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:logging/logging.dart';

import '../clock.dart';
import '../devices/devices.dart';
import '../logging.dart';
import '../media/media_store.dart';
import '../playlists/playlist_store.dart';

final _log = Logger('realtime');

/// Canal de uma TV conectada, isolado do WebSocket para facilitar os testes.
abstract interface class DeviceConnection {
  /// Envia [envelope] à TV.
  void send(Envelope envelope);

  /// Fecha a conexão com o [code] e o [reason] dados.
  Future<void> close(int code, String reason);
}

/// Registro em memória das TVs online e ponto único de emissão de eventos
/// para os dashboards.
class DeviceHub {
  DeviceHub({
    required DeviceStore devices,
    required MediaStore media,
    required PlaylistStore playlists,
    Clock clock = DateTime.now,
  }) : _devices = devices,
       _media = media,
       _playlists = playlists,
       _clock = clock;

  /// Intervalo mínimo entre duas gravações de `last_seen_at` por TV.
  static const touchInterval = Duration(minutes: 1);

  final DeviceStore _devices;
  final MediaStore _media;
  final PlaylistStore _playlists;
  final Clock _clock;
  final _connections = <String, DeviceConnection>{};
  final _currentItems = <String, String>{};
  final _lastTouch = <String, DateTime>{};
  final _sentRevisions = <String, String>{};
  final _events = StreamController<Envelope>.broadcast();

  /// Eventos para o `/ws/admin`.
  Stream<Envelope> get events => _events.stream;

  bool isOnline(String deviceId) => _connections.containsKey(deviceId);

  /// Ids das TVs conectadas agora.
  List<String> get onlineIds => _connections.keys.toList();

  /// `revision` do último `content.sync` enviado à TV nesta conexão.
  String? sentRevisionOf(String deviceId) => _sentRevisions[deviceId];

  /// Anota o `revision` enviado à TV [deviceId].
  void rememberRevision(String deviceId, String revision) =>
      _sentRevisions[deviceId] = revision;

  /// O que a TV informou estar exibindo; some quando ela desconecta.
  String? currentItemOf(String deviceId) => _currentItems[deviceId];

  /// Junta os dados do banco com o estado em memória.
  DeviceSummary summaryOf(DeviceRow row) {
    final mediaId = row.mediaId;
    final media = mediaId == null ? null : _media.find(mediaId);
    final playlistId = row.playlistId;
    final playlist = playlistId == null ? null : _playlists.find(playlistId);
    return DeviceSummary(
      id: row.id,
      name: row.name,
      online: isOnline(row.id),
      createdAt: row.createdAt,
      info: row.info,
      groupId: row.groupId,
      lastSeenAt: row.lastSeenAt,
      currentItem: currentItemOf(row.id),
      content: media?.toContentItem(),
      playlist: playlist == null
          ? null
          : PlaylistRef(id: playlist.id, name: playlist.name),
    );
  }

  List<DeviceSummary> summaries() => [
    for (final row in _devices.list()) summaryOf(row),
  ];

  /// Envia [envelope] à TV. Devolve `false` se ela está offline.
  bool send(String deviceId, Envelope envelope) {
    final conn = _connections[deviceId];
    if (conn == null) return false;
    conn.send(envelope);
    return true;
  }

  /// Registra a conexão da TV. Uma conexão anterior é fechada com
  /// [WsCloseCodes.replaced].
  void attach(String deviceId, DeviceConnection conn) {
    final old = _connections[deviceId];
    _connections[deviceId] = conn;
    _sentRevisions.remove(deviceId);
    if (old != null && !identical(old, conn)) {
      _log.info(LogEvent('conexão substituída', {'deviceId': deviceId}));
      unawaited(old.close(WsCloseCodes.replaced, 'replaced'));
    }
  }

  /// Remove [conn] se ela ainda for a conexão atual da TV e avisa os
  /// dashboards com `device.offline`.
  void detach(String deviceId, DeviceConnection conn) {
    if (!identical(_connections[deviceId], conn)) return;
    _connections.remove(deviceId);
    _currentItems.remove(deviceId);
    _lastTouch.remove(deviceId);
    _sentRevisions.remove(deviceId);
    final now = _clock();
    _devices.touch(deviceId, now);
    publish(MessageTypes.deviceOffline, {
      'deviceId': deviceId,
      'lastSeenAt': isoUtc(now),
    });
  }

  /// Fecha a conexão da TV sem avisar `device.offline` (ex.: TV removida).
  void disconnect(String deviceId, int closeCode) {
    final conn = _connections.remove(deviceId);
    _currentItems.remove(deviceId);
    _lastTouch.remove(deviceId);
    _sentRevisions.remove(deviceId);
    if (conn != null) unawaited(conn.close(closeCode, 'disconnected'));
  }

  /// Anota que a TV deu sinal de vida.
  ///
  /// Grava `last_seen_at` no máximo uma vez por [touchInterval]. Se o
  /// [currentItem] mudou, publica `device.state`, a não ser que [announce]
  /// seja `false` (o `hello` já publica o estado completo).
  void markSeen(String deviceId, {String? currentItem, bool announce = true}) {
    final now = _clock();
    final last = _lastTouch[deviceId];
    if (last == null || now.difference(last) >= touchInterval) {
      _devices.touch(deviceId, now);
      _lastTouch[deviceId] = now;
    }
    final changed = _currentItems[deviceId] != currentItem;
    if (currentItem == null) {
      _currentItems.remove(deviceId);
    } else {
      _currentItems[deviceId] = currentItem;
    }
    if (changed && announce) {
      final row = _devices.find(deviceId);
      if (row != null) {
        publish(MessageTypes.deviceState, summaryOf(row).toJson());
      }
    }
  }

  /// Envia um evento a todos os dashboards conectados.
  void publish(String type, Map<String, Object?> payload) =>
      _events.add(Envelope.create(type, payload: payload, now: _clock()));
}
