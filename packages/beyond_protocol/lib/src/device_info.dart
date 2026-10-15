import 'json_fields.dart';

/// Dados que a TV informa sobre si no pareamento (e, depois, no `hello`).
///
/// Só [appVersion] é obrigatório: TVs diferentes expõem informações
/// diferentes, e o servidor guarda o que vier.
final class DeviceInfo {
  const DeviceInfo({
    required this.appVersion,
    this.manufacturer,
    this.model,
    this.androidVersion,
    this.screenWidth,
    this.screenHeight,
  });

  factory DeviceInfo.fromJson(Map<String, Object?> json) => DeviceInfo(
        appVersion: json.field<String>('appVersion'),
        manufacturer: json.optionalField<String>('manufacturer'),
        model: json.optionalField<String>('model'),
        androidVersion: json.optionalField<String>('androidVersion'),
        screenWidth: json.optionalField<int>('screenWidth'),
        screenHeight: json.optionalField<int>('screenHeight'),
      );

  /// Versão do app Beyond TV (ex.: `0.4.0`).
  final String appVersion;

  /// Fabricante (ex.: `Xiaomi`).
  final String? manufacturer;

  /// Modelo (ex.: `MiTV-AXSO0`).
  final String? model;

  /// Versão do Android (ex.: `11`).
  final String? androidVersion;

  /// Resolução da tela em pixels físicos.
  final int? screenWidth;
  final int? screenHeight;

  /// Nome sugerido para a TV recém-pareada, até o administrador renomeá-la.
  String get suggestedName => switch ((manufacturer, model)) {
        (final maker?, final model?)
            when model.toLowerCase().startsWith(maker.toLowerCase()) =>
          model,
        (final maker?, final model?) => '$maker $model',
        (null, final model?) => model,
        _ => 'Nova TV',
      };

  Map<String, Object?> toJson() => {
        'appVersion': appVersion,
        if (manufacturer != null) 'manufacturer': manufacturer,
        if (model != null) 'model': model,
        if (androidVersion != null) 'androidVersion': androidVersion,
        if (screenWidth != null) 'screenWidth': screenWidth,
        if (screenHeight != null) 'screenHeight': screenHeight,
      };

  @override
  bool operator ==(Object other) =>
      other is DeviceInfo &&
      other.appVersion == appVersion &&
      other.manufacturer == manufacturer &&
      other.model == model &&
      other.androidVersion == androidVersion &&
      other.screenWidth == screenWidth &&
      other.screenHeight == screenHeight;

  @override
  int get hashCode => Object.hash(
        appVersion,
        manufacturer,
        model,
        androidVersion,
        screenWidth,
        screenHeight,
      );

  @override
  String toString() => 'DeviceInfo($suggestedName, app $appVersion)';
}
