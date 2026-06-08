import 'dart:convert';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';

class RemoteConfigService {
  static final RemoteConfigService _instance = RemoteConfigService._internal();

  factory RemoteConfigService() {
    return _instance;
  }

  RemoteConfigService._internal();

  final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;

  Future<void> initialize() async {
    try {
      await _remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(minutes: 1),
        minimumFetchInterval: const Duration(hours: 1),
      ));

      await _remoteConfig.setDefaults({
        'min_required_version': '1.0.0',
        'is_maintenance_mode': false,
      });

      await fetchAndActivate();
    } catch (e) {
      // print('Remote Config initialization failed: $e');
    }
  }

  Future<bool> fetchAndActivate() async {
    try {
      return await _remoteConfig.fetchAndActivate();
    } catch (e) {
      // print('Remote Config fetch failed: $e');
      return false;
    }
  }

  bool get isMaintenanceMode => _remoteConfig.getBool('is_maintenance_mode');

  String get minRequiredVersion =>
      _remoteConfig.getString('min_required_version');

  Future<bool> isUpdateRequired() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final minVersion = minRequiredVersion;

      return _compareVersions(currentVersion, minVersion) < 0;
    } catch (e) {
      // print('Version check failed: $e');
      return false;
    }
  }

  int _compareVersions(String v1, String v2) {
    final v1Parts = v1.split('.').map(int.parse).toList();
    final v2Parts = v2.split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      final part1 = i < v1Parts.length ? v1Parts[i] : 0;
      final part2 = i < v2Parts.length ? v2Parts[i] : 0;

      if (part1 < part2) return -1;
      if (part1 > part2) return 1;
    }
    return 0;
  }

  List<String> getApprovedDomains() {
    try {
      final jsonString = _remoteConfig.getString('approved_domains');
      final List<dynamic> list =
          _remoteConfig.getAll().containsKey('approved_domains')
              ? jsonDecode(jsonString)
              : [];
      return list.map((e) => e.toString()).toList();
    } catch (e) {
      // print('Failed to parse approved_domains: $e');
      return [];
    }
  }
}
