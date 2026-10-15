import 'dart:io';
import 'dart:ui';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Versão do app enviada ao servidor. Mantenha igual à do `pubspec.yaml`
/// (um teste confere).
const appVersion = '1.0.0';

/// De onde vêm os dados da TV enviados no pareamento.
abstract interface class DeviceInfoSource {
  Future<DeviceInfo> read();
}

/// Lê fabricante, modelo e versão do Android do sistema, e a resolução da
/// tela do Flutter.
class PlatformDeviceInfoSource implements DeviceInfoSource {
  const PlatformDeviceInfoSource();

  @override
  Future<DeviceInfo> read() async {
    final size = PlatformDispatcher.instance.views.firstOrNull?.physicalSize;
    final screenWidth = size?.width.round();
    final screenHeight = size?.height.round();

    if (!Platform.isAndroid) {
      return DeviceInfo(
        appVersion: appVersion,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
      );
    }
    final android = await DeviceInfoPlugin().androidInfo;
    return DeviceInfo(
      appVersion: appVersion,
      manufacturer: android.manufacturer,
      model: android.model,
      androidVersion: android.version.release,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
    );
  }
}
