import 'dart:io';

import 'package:beyond_tv/src/device/device_info_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('appVersion acompanha a versão do pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*([\d.]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);

    expect(appVersion, version);
  });
}
