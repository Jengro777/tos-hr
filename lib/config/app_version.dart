import 'package:package_info_plus/package_info_plus.dart';

class AppVersionInfo {
  const AppVersionInfo({required this.version, this.buildNumber = ''});

  const AppVersionInfo.unknown() : version = '', buildNumber = '';

  final String version;
  final String buildNumber;

  bool get isAvailable => version.trim().isNotEmpty;

  String get displayText {
    final normalizedVersion = version.trim();
    final normalizedBuildNumber = buildNumber.trim();
    if (normalizedBuildNumber.isEmpty) {
      return '版本 $normalizedVersion';
    }
    return '版本 $normalizedVersion（构建 $normalizedBuildNumber）';
  }

  static Future<AppVersionInfo> load() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return AppVersionInfo(
        version: packageInfo.version,
        buildNumber: packageInfo.buildNumber,
      );
    } catch (_) {
      return const AppVersionInfo.unknown();
    }
  }
}
