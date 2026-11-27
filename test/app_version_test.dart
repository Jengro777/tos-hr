import 'package:flutter_test/flutter_test.dart';
import 'package:tospino_hr/config/app_version.dart';

void main() {
  test('formats the app version and optional build number', () {
    const version = AppVersionInfo(version: '0.1.14');
    const versionWithBuild = AppVersionInfo(
      version: '0.1.14',
      buildNumber: '27',
    );

    expect(version.displayText, '版本 0.1.14');
    expect(versionWithBuild.displayText, '版本 0.1.14（构建 27）');
    expect(version.isAvailable, isTrue);
  });

  test('hides unavailable version information', () {
    const version = AppVersionInfo.unknown();

    expect(version.isAvailable, isFalse);
  });
}
