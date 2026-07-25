import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Reads [AndroidDeviceInfo.manufacturer] (or brand as fallback). Null on
/// non-Android / failures — OEM matching then shows the generic path.
///
/// Isolated so Status / Onboarding can inject a stub under `flutter_test`
/// without pulling the plugin channel.
Future<String?> readDeviceManufacturer() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return null;
  }
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    final manufacturer = info.manufacturer.trim();
    if (manufacturer.isNotEmpty) return manufacturer;
    final brand = info.brand.trim();
    return brand.isEmpty ? null : brand;
  } catch (_) {
    return null;
  }
}
