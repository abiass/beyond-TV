import 'package:beyond_protocol/beyond_protocol.dart';

import '../devices/devices.dart';
import '../groups/group_store.dart';
import '../media/media_store.dart';
import '../playlists/playlist_store.dart';
import '../schedules/schedule_store.dart';
import 'device_hub.dart';

/// Monta e envia o `content.sync` das TVs.
class ContentSync {
  ContentSync({
    required DeviceStore devices,
    required GroupStore groups,
    required ScheduleStore schedules,
    required MediaStore media,
    required PlaylistStore playlists,
    required DeviceHub hub,
  }) : _devices = devices,
       _groups = groups,
       _schedules = schedules,
       _media = media,
       _playlists = playlists,
       _hub = hub;

  final DeviceStore _devices;
  final GroupStore _groups;
  final ScheduleStore _schedules;
  final MediaStore _media;
  final PlaylistStore _playlists;
  final DeviceHub _hub;

  /// O que a TV [deviceId] deve exibir: o conteúdo padrão (o da TV ou, se ela
  /// não tem, o do grupo) e os agendamentos, na ordem de precedência.
  ContentManifest manifestFor(String deviceId) {
    final row = _devices.find(deviceId);
    if (row == null) return ContentManifest.empty;
    final hasOwn = row.mediaId != null || row.playlistId != null;
    final group = row.groupId == null ? null : _groups.find(row.groupId!);
    final defaults = hasOwn
        ? _itemsOf(row.mediaId, row.playlistId)
        : _itemsOf(group?.mediaId, group?.playlistId);
    return ContentManifest(
      items: defaults,
      schedules: [
        for (final s in _schedules.forDevice(deviceId, row.groupId))
          ScheduleRule(
            id: s.id,
            days: s.data.days,
            startMinute: s.data.startMinute,
            endMinute: s.data.endMinute,
            priority: s.data.priority,
            target: s.target,
            items: _itemsOf(null, s.data.playlistId),
          ),
      ],
    );
  }

  List<ContentItem> _itemsOf(String? mediaId, String? playlistId) {
    if (playlistId != null) {
      return [
        for (final item in _playlists.itemsOf(playlistId))
          item.media.toContentItem(durationSeconds: item.durationSeconds),
      ];
    }
    final media = mediaId == null ? null : _media.find(mediaId);
    return media == null ? const [] : [media.toContentItem()];
  }

  /// Manda o manifesto atual à TV, se ela estiver online, e anota o
  /// `revision` enviado.
  void syncDevice(String deviceId) => _push(deviceId, manifestFor(deviceId));

  /// Recalcula o manifesto de cada TV online e manda `content.sync` só às
  /// que tiveram o `revision` alterado desde o último envio.
  void syncOnline() {
    for (final deviceId in _hub.onlineIds) {
      final manifest = manifestFor(deviceId);
      if (_hub.sentRevisionOf(deviceId) != manifest.revision) {
        _push(deviceId, manifest);
      }
    }
  }

  void _push(String deviceId, ContentManifest manifest) {
    final sent = _hub.send(
      deviceId,
      Envelope.create(MessageTypes.contentSync, payload: manifest.toJson()),
    );
    if (sent) _hub.rememberRevision(deviceId, manifest.revision);
  }
}
