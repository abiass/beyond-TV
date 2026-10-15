import 'package:beyond_tv/src/system/system_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PlatformSystemSettings.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('getStatus lê o mapa nativo', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getStatus');
      return {
        'startOnBoot': true,
        'canDrawOverlays': false,
        'sdkInt': 33,
        'kioskEnabled': true,
        'isDefaultLauncher': false,
      };
    });

    final status = await const PlatformSystemSettings().getStatus();

    expect(status.available, isTrue);
    expect(status.startOnBoot, isTrue);
    expect(status.canDrawOverlays, isFalse);
    expect(status.sdkInt, 33);
    expect(status.kioskEnabled, isTrue);
    expect(status.isDefaultLauncher, isFalse);
    expect(status.needsOverlayPermission, isTrue);
    expect(status.kioskActive, isFalse);
  });

  test('setStartOnBoot e setKioskEnabled mandam enabled', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    const settings = PlatformSystemSettings();

    await settings.setStartOnBoot(false);
    await settings.setKioskEnabled(true);

    expect(calls.map((c) => c.method), ['setStartOnBoot', 'setKioskEnabled']);
    expect(calls[0].arguments, {'enabled': false});
    expect(calls[1].arguments, {'enabled': true});
  });

  test('openOverlaySettings e openHomeSettings devolvem o resultado', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return call.method == 'openHomeSettings';
    });
    const settings = PlatformSystemSettings();

    expect(await settings.openOverlaySettings(), isFalse);
    expect(await settings.openHomeSettings(), isTrue);
  });

  test('canal ausente devolve status indisponível sem lançar', () async {
    const settings = PlatformSystemSettings();

    expect(await settings.getStatus(), SystemStatus.unavailable);
    await settings.setStartOnBoot(true);
    await settings.setKioskEnabled(true);
    expect(await settings.openOverlaySettings(), isFalse);
    expect(await settings.openHomeSettings(), isFalse);
  });

  test('erro nativo também vira indisponível', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'system_failed');
    });
    const settings = PlatformSystemSettings();

    expect(await settings.getStatus(), SystemStatus.unavailable);
    await settings.setKioskEnabled(true);
  });

  test('quiosque só vale com o app como launcher padrão', () {
    const base = SystemStatus(
      startOnBoot: true,
      canDrawOverlays: true,
      sdkInt: 33,
      kioskEnabled: true,
      isDefaultLauncher: true,
    );
    expect(base.kioskActive, isTrue);
    expect(base.needsOverlayPermission, isFalse);
    expect(base.copyWith(kioskEnabled: false).kioskActive, isFalse);
    expect(SystemStatus.unavailable.kioskActive, isFalse);
  });
}
