import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/sessions.dart';
import '../devices/devices.dart';
import '../groups/group_store.dart';
import '../http/json.dart';
import '../logging.dart';
import '../media/media_validation.dart';
import '../playlists/playlist_store.dart';
import '../realtime/content_sync.dart';
import '../schedules/schedule_store.dart';

final _log = Logger('schedules');

/// Rotas de agendamentos (todas de admin).
///
/// - `GET /api/v1/schedules?deviceId=` ou `?groupId=`: lista (filtra pelo alvo).
/// - `POST /api/v1/schedules`: cria.
/// - `GET/PATCH/DELETE /api/v1/schedules/<id>`: lê, altera e apaga.
class SchedulesApi {
  SchedulesApi({
    required SessionStore sessions,
    required ScheduleStore schedules,
    required PlaylistStore playlists,
    required DeviceStore devices,
    required GroupStore groups,
    required ContentSync sync,
  }) : _sessions = sessions,
       _schedules = schedules,
       _playlists = playlists,
       _devices = devices,
       _groups = groups,
       _sync = sync;

  final SessionStore _sessions;
  final ScheduleStore _schedules;
  final PlaylistStore _playlists;
  final DeviceStore _devices;
  final GroupStore _groups;
  final ContentSync _sync;

  void addRoutes(Router router) {
    final admin = const Pipeline().addMiddleware(_sessions.requireAdmin());
    router
      ..get('/api/v1/schedules', admin.addHandler(_list))
      ..post('/api/v1/schedules', admin.addHandler(_create))
      ..get('/api/v1/schedules/<id>', admin.addHandler(_get))
      ..patch('/api/v1/schedules/<id>', admin.addHandler(_update))
      ..delete('/api/v1/schedules/<id>', admin.addHandler(_delete));
  }

  Response _list(Request request) {
    final query = request.url.queryParameters;
    final groupParam = query['groupId'];
    final groupId = groupParam == null ? null : int.tryParse(groupParam);
    if (groupParam != null && groupId == null) {
      throw const ApiException.badRequest('Parâmetro "groupId" inválido.');
    }
    final rows = _schedules.list(deviceId: query['deviceId'], groupId: groupId);
    return jsonResponse({
      'schedules': [for (final s in rows) s.toJson()],
    });
  }

  Future<Response> _create(Request request) async {
    final body = await readJsonObject(request);
    final row = _schedules.create(_validate(body));
    _sync.syncOnline();
    _log.info(LogEvent('agendamento criado', {'scheduleId': row.id}));
    return jsonResponse(row.toJson(), status: 201);
  }

  Response _get(Request request) => jsonResponse(_find(request).toJson());

  Future<Response> _update(Request request) async {
    final current = _find(request);
    final body = await readJsonObject(request);
    // Mudar o alvo vale pelo que o corpo diz: o alvo antigo não entra na
    // mistura, senão trocar de TV para grupo nunca passaria na validação.
    final changesTarget =
        body.containsKey('deviceId') || body.containsKey('groupId');
    final merged = <String, Object?>{
      ...current.toJson(),
      if (changesTarget) ...{'deviceId': null, 'groupId': null},
      for (final key in _fields)
        if (body.containsKey(key)) key: body[key],
    };
    _schedules.update(current.id, _validate(merged));
    _sync.syncOnline();
    return jsonResponse(_schedules.find(current.id)!.toJson());
  }

  Response _delete(Request request) {
    final id = _find(request).id;
    _schedules.delete(id);
    _sync.syncOnline();
    _log.info(LogEvent('agendamento removido', {'scheduleId': id}));
    return Response(204);
  }

  static const _fields = [
    'name',
    'playlistId',
    'deviceId',
    'groupId',
    'days',
    'start',
    'end',
    'priority',
  ];

  /// Valida o corpo completo e devolve os campos tipados.
  ScheduleData _validate(Map<String, Object?> body) {
    final name = validateMediaName(body['name']);

    final playlistId = body['playlistId'];
    if (playlistId is! String || _playlists.find(playlistId) == null) {
      throw const ApiException(
        400,
        'unknown_playlist',
        'A playlist informada não existe.',
      );
    }

    final deviceId = body['deviceId'];
    final groupId = body['groupId'];
    if ((deviceId == null) == (groupId == null)) {
      throw const ApiException.badRequest(
        'Informe "deviceId" ou "groupId" (apenas um).',
      );
    }
    if (deviceId != null &&
        (deviceId is! String || _devices.find(deviceId) == null)) {
      throw const ApiException(
        400,
        'unknown_device',
        'A TV informada não existe.',
      );
    }
    if (groupId != null && (groupId is! int || _groups.find(groupId) == null)) {
      throw const ApiException(
        400,
        'unknown_group',
        'O grupo informado não existe.',
      );
    }

    final rawDays = body['days'];
    final days = <int>{};
    if (rawDays is! List<Object?> || rawDays.isEmpty) {
      throw _invalidDays;
    }
    for (final day in rawDays) {
      if (day is! int ||
          day < DateTime.monday ||
          day > DateTime.sunday ||
          !days.add(day)) {
        throw _invalidDays;
      }
    }

    final start = _clock(body['start']);
    final end = _clock(body['end']);

    final priority = body['priority'];
    if (priority is! int || priority < 0 || priority > maxSchedulePriority) {
      throw const ApiException(
        400,
        'invalid_priority',
        'A prioridade deve ser um inteiro de 0 a $maxSchedulePriority.',
      );
    }

    return ScheduleData(
      name: name,
      playlistId: playlistId,
      deviceId: deviceId as String?,
      groupId: groupId as int?,
      days: days,
      startMinute: start,
      endMinute: end,
      priority: priority,
    );
  }

  int _clock(Object? value) {
    final minutes = value is String ? parseClockTime(value) : null;
    if (minutes == null) {
      throw const ApiException(
        400,
        'invalid_time',
        'Use o horário no formato HH:MM, de 00:00 a 23:59.',
      );
    }
    return minutes;
  }

  static const _invalidDays = ApiException(
    400,
    'invalid_days',
    'Informe ao menos um dia, de 1 (segunda) a 7 (domingo), sem repetir.',
  );

  ScheduleRow _find(Request request) =>
      _schedules.find(request.params['id']!) ??
      (throw const ApiException.notFound('Agendamento não encontrado.'));
}
