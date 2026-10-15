import 'content.dart';
import 'playlists.dart';
import 'device_info.dart';
import 'json_fields.dart';

/// Rotas WebSocket do servidor.
abstract final class WsPaths {
  /// Conexão de cada TV, autenticada por `Authorization: Bearer <token>`.
  static const device = '/ws/device';

  /// Eventos ao vivo para o dashboard, autenticada pelo cookie de sessão.
  static const admin = '/ws/admin';
}

/// Intervalo entre os `heartbeat` da TV.
const heartbeatInterval = Duration(seconds: 30);

/// Sem nenhuma mensagem da TV por este tempo, o servidor a considera offline.
const deviceSilenceTimeout = Duration(seconds: 90);

/// Prazo para a TV mandar o `hello` depois de conectar.
const helloTimeout = Duration(seconds: 10);

/// Códigos de fechamento do WebSocket (faixa 4000–4999, de aplicação).
abstract final class WsCloseCodes {
  /// Token ou sessão inválidos, ou TV removida. A TV apaga as credenciais e
  /// volta para o pareamento; o dashboard volta para o login.
  static const unauthorized = 4401;

  /// A TV não mandou `hello` a tempo ou mandou mensagem fora do protocolo.
  static const protocolError = 4400;

  /// Uma conexão mais nova da mesma TV substituiu esta. Não reconectar.
  static const replaced = 4409;

  /// Versão de protocolo incompatível: "atualize o app da TV".
  static const incompatibleVersion = 4426;
}

/// Payload do `hello`, primeira mensagem da TV em cada conexão.
final class HelloPayload {
  const HelloPayload({required this.deviceInfo, this.currentItem});

  factory HelloPayload.fromJson(Map<String, Object?> json) => HelloPayload(
        deviceInfo: DeviceInfo.fromJson(
          json.field<Map<String, Object?>>('deviceInfo'),
        ),
        currentItem: json.optionalField<String>('currentItem'),
      );

  final DeviceInfo deviceInfo;

  /// O que a TV está exibindo agora (ex.: a URL), se houver.
  final String? currentItem;

  Map<String, Object?> toJson() => {
        'deviceInfo': deviceInfo.toJson(),
        if (currentItem != null) 'currentItem': currentItem,
      };
}

/// Payload do `heartbeat`, enviado a cada [heartbeatInterval].
final class HeartbeatPayload {
  const HeartbeatPayload({required this.uptimeSeconds, this.currentItem});

  factory HeartbeatPayload.fromJson(Map<String, Object?> json) =>
      HeartbeatPayload(
        uptimeSeconds: json.field<int>('uptimeSeconds'),
        currentItem: json.optionalField<String>('currentItem'),
      );

  /// Segundos desde que o app abriu.
  final int uptimeSeconds;
  final String? currentItem;

  Map<String, Object?> toJson() => {
        'uptimeSeconds': uptimeSeconds,
        if (currentItem != null) 'currentItem': currentItem,
      };
}

/// Uma TV como o dashboard a vê: em `GET /api/v1/devices` e nos eventos
/// `device.paired` e `device.state`.
final class DeviceSummary {
  DeviceSummary({
    required this.id,
    required this.name,
    required this.online,
    required DateTime createdAt,
    this.info,
    this.groupId,
    DateTime? lastSeenAt,
    this.currentItem,
    this.content,
    this.playlist,
  })  : createdAt = createdAt.toUtc(),
        lastSeenAt = lastSeenAt?.toUtc();

  factory DeviceSummary.fromJson(Map<String, Object?> json) {
    final info = json.optionalField<Map<String, Object?>>('info');
    final lastSeen = json.optionalField<String>('lastSeenAt');
    final content = json.optionalField<Map<String, Object?>>('content');
    final playlist = json.optionalField<Map<String, Object?>>('playlist');
    return DeviceSummary(
      id: json.field<String>('id'),
      name: json.field<String>('name'),
      online: json.field<bool>('online'),
      createdAt: json.dateField('createdAt'),
      info: info == null || info.isEmpty ? null : DeviceInfo.fromJson(info),
      groupId: json.optionalField<int>('groupId'),
      lastSeenAt: lastSeen == null ? null : json.dateField('lastSeenAt'),
      currentItem: json.optionalField<String>('currentItem'),
      content: content == null ? null : ContentItem.fromJson(content),
      playlist: playlist == null ? null : PlaylistRef.fromJson(playlist),
    );
  }

  final String id;
  final String name;

  /// Se a TV tem um WebSocket aberto com o servidor agora.
  final bool online;
  final DateTime createdAt;

  /// Dados do último `hello` (ou do pareamento).
  final DeviceInfo? info;
  final int? groupId;

  /// Última mensagem recebida da TV.
  final DateTime? lastSeenAt;

  /// O que a TV informou estar exibindo no último `hello`/`heartbeat`.
  final String? currentItem;

  /// A mídia avulsa que o painel mandou esta TV exibir.
  ///
  /// [content] e [playlist] nunca vêm juntos; os dois `null` = sem conteúdo.
  final ContentItem? content;

  /// A playlist que o painel mandou esta TV exibir.
  final PlaylistRef? playlist;

  DeviceSummary copyWith({
    String? name,
    bool? online,
    DateTime? lastSeenAt,
    String? currentItem,
  }) =>
      DeviceSummary(
        id: id,
        name: name ?? this.name,
        online: online ?? this.online,
        createdAt: createdAt,
        info: info,
        groupId: groupId,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        currentItem: currentItem ?? this.currentItem,
        content: content,
        playlist: playlist,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'online': online,
        'createdAt': createdAt.toIso8601String(),
        if (info != null) 'info': info!.toJson(),
        'groupId': groupId,
        'lastSeenAt': lastSeenAt?.toIso8601String(),
        if (currentItem != null) 'currentItem': currentItem,
        'content': content?.toJson(),
        'playlist': playlist?.toJson(),
      };
}
