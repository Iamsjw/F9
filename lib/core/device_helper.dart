import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceHelper {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static String? _cachedDeviceId;

  /// Retrieves a unique hardware device identifier with an automatic
  /// fallback to a persistent generated UUID stored in SharedPreferences.
  static Future<String> getUniqueDeviceId() async {
    if (_cachedDeviceId != null && _cachedDeviceId!.isNotEmpty) {
      return _cachedDeviceId!;
    }

    try {
      if (kIsWeb) {
        _cachedDeviceId = await _getOrCreateFallbackId('web_device_id');
        return _cachedDeviceId!;
      }

      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        final id = androidInfo.id.trim();
        if (id.isNotEmpty && id != 'unknown') {
          _cachedDeviceId = id;
          return _cachedDeviceId!;
        }
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        final id = iosInfo.identifierForVendor?.trim() ?? '';
        if (id.isNotEmpty && id != 'unknown') {
          _cachedDeviceId = id;
          return _cachedDeviceId!;
        }
      }
    } catch (e) {
      debugPrint('[DeviceHelper] Error getting hardware ID: $e');
    }

    // Fallback to stored persistent UUID
    _cachedDeviceId = await _getOrCreateFallbackId('app_fallback_device_id');
    return _cachedDeviceId!;
  }

  static Future<String> _getOrCreateFallbackId(String prefKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? existing = prefs.getString(prefKey);
      if (existing != null && existing.isNotEmpty) {
        return existing;
      }
      final newId = 'dev_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (DateTime.now().microsecond % 9000))}';
      await prefs.setString(prefKey, newId);
      return newId;
    } catch (_) {
      return 'fallback_${DateTime.now().millisecondsSinceEpoch}';
    }
  }
}
