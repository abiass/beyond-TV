import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Estado das opções de sistema da TV (abrir ao ligar, quiosque).
class SystemStatus {
  const SystemStatus({
    required this.startOnBoot,
    required this.canDrawOverlays,
    required this.sdkInt,
    required this.kioskEnabled,
    required this.isDefaultLauncher,
    this.available = true,
  });

  /// Fora do Android (ou sem o lado nativo): nada a configurar.
  static const unavailable = SystemStatus(
    startOnBoot: false,
    canDrawOverlays: false,
    sdkInt: 0,
    kioskEnabled: false,
    isDefaultLauncher: false,
    available: false,
  );

  final bool startOnBoot;
  final bool canDrawOverlays;
  final int sdkInt;
  final bool kioskEnabled;
  final bool isDefaultLauncher;
  final bool available;

  /// Android 10+ bloqueia abrir o app sozinho sem sobreposição ou launcher.
  bool get needsOverlayPermission =>
      available && sdkInt >= 29 && !canDrawOverlays;

  /// Modo quiosque ativo de fato: o Voltar não pode sair do app.
  bool get kioskActive => available && kioskEnabled && isDefaultLauncher;

  SystemStatus copyWith({bool? startOnBoot, bool? kioskEnabled}) =>
      SystemStatus(
        startOnBoot: startOnBoot ?? this.startOnBoot,
        canDrawOverlays: canDrawOverlays,
        sdkInt: sdkInt,
        kioskEnabled: kioskEnabled ?? this.kioskEnabled,
        isDefaultLauncher: isDefaultLauncher,
        available: available,
      );

  @override
  bool operator ==(Object other) =>
      other is SystemStatus &&
      other.startOnBoot == startOnBoot &&
      other.canDrawOverlays == canDrawOverlays &&
      other.sdkInt == sdkInt &&
      other.kioskEnabled == kioskEnabled &&
      other.isDefaultLauncher == isDefaultLauncher &&
      other.available == available;

  @override
  int get hashCode => Object.hash(
        startOnBoot,
        canDrawOverlays,
        sdkInt,
        kioskEnabled,
        isDefaultLauncher,
        available,
      );
}

/// Opções de sistema do Android: abrir ao ligar e modo quiosque.
abstract interface class SystemSettings {
  Future<SystemStatus> getStatus();

  Future<void> setStartOnBoot(bool enabled);

  Future<void> setKioskEnabled(bool enabled);

  /// Abre a tela "sobrepor a outros apps"; `false` se a TV não a tem.
  Future<bool> openOverlaySettings();

  /// Abre a escolha do launcher padrão; `false` se nada pôde ser aberto.
  Future<bool> openHomeSettings();
}

/// Fala com o lado nativo pelo canal `beyond_tv/system`. Sem o lado nativo
/// (testes, fora do Android), devolve [SystemStatus.unavailable].
class PlatformSystemSettings implements SystemSettings {
  const PlatformSystemSettings({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'beyond_tv/system';

  final MethodChannel _channel;

  @override
  Future<SystemStatus> getStatus() async {
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('getStatus');
      if (map == null) return SystemStatus.unavailable;
      return SystemStatus(
        startOnBoot: map['startOnBoot'] == true,
        canDrawOverlays: map['canDrawOverlays'] == true,
        sdkInt: map['sdkInt'] is int ? map['sdkInt']! as int : 0,
        kioskEnabled: map['kioskEnabled'] == true,
        isDefaultLauncher: map['isDefaultLauncher'] == true,
      );
    } on MissingPluginException {
      return SystemStatus.unavailable;
    } on PlatformException {
      return SystemStatus.unavailable;
    }
  }

  @override
  Future<void> setStartOnBoot(bool enabled) =>
      _call('setStartOnBoot', {'enabled': enabled});

  @override
  Future<void> setKioskEnabled(bool enabled) =>
      _call('setKioskEnabled', {'enabled': enabled});

  @override
  Future<bool> openOverlaySettings() => _callBool('openOverlaySettings');

  @override
  Future<bool> openHomeSettings() => _callBool('openHomeSettings');

  Future<void> _call(String method, Object? args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // Sem o lado nativo: nada a fazer.
    } on PlatformException {
      // O nativo recusou: o menu relê o status e mostra o estado real.
    }
  }

  Future<bool> _callBool(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

/// Entrega o [SystemSettings] à árvore, como o capturador de tela.
class SystemSettingsScope extends InheritedWidget {
  const SystemSettingsScope({
    super.key,
    required this.settings,
    required super.child,
  });

  final SystemSettings settings;

  /// Sem escopo na árvore, usa o canal nativo.
  static SystemSettings of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<SystemSettingsScope>();
    return scope?.settings ?? const PlatformSystemSettings();
  }

  @override
  bool updateShouldNotify(SystemSettingsScope oldWidget) =>
      settings != oldWidget.settings;
}
