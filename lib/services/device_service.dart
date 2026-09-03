import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';

import '../utils/constants.dart';

/// Secure storage wrapper with timeout guard.
class SecureStore {
  static const _storage = FlutterSecureStorage();

  static Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key).timeout(AppConstants.storageTimeout);
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value).timeout(AppConstants.storageTimeout);
    } catch (_) {}
  }

  static Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key).timeout(AppConstants.storageTimeout);
    } catch (_) {}
  }
}

class DeviceService {
  static String? _cachedDeviceId;

  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    final stored = await SecureStore.read('sj_act_device_id');
    if (stored != null && stored.isNotEmpty) {
      _cachedDeviceId = stored;
      return stored;
    }

    String rawId;
    try {
      final infoPlugin = DeviceInfoPlugin();
      if (kIsWeb) {
        rawId = 'web-${DateTime.now().millisecondsSinceEpoch}';
      } else if (Platform.isAndroid) {
        final info = await infoPlugin.androidInfo.timeout(AppConstants.storageTimeout);
        rawId = info.id + info.fingerprint;
      } else if (Platform.isIOS) {
        final info = await infoPlugin.iosInfo.timeout(AppConstants.storageTimeout);
        rawId = info.identifierForVendor ?? info.name;
      } else {
        rawId = 'unknown-${DateTime.now().millisecondsSinceEpoch}';
      }
    } catch (_) {
      rawId = 'fallback-${DateTime.now().millisecondsSinceEpoch}';
    }

    final deviceId = sha256.convert(utf8.encode(rawId)).toString();
    await SecureStore.write('sj_act_device_id', deviceId);
    _cachedDeviceId = deviceId;
    return deviceId;
  }

  static Future<String> getDeviceFingerprint() async {
    try {
      final infoPlugin = DeviceInfoPlugin();
      String raw;
      if (!kIsWeb && Platform.isAndroid) {
        final info = await infoPlugin.androidInfo.timeout(AppConstants.storageTimeout);
        raw = '${info.brand}-${info.model}-${info.board}-${info.hardware}';
      } else if (!kIsWeb && Platform.isIOS) {
        final info = await infoPlugin.iosInfo.timeout(AppConstants.storageTimeout);
        raw = '${info.model}-${info.systemName}-${info.utsname.machine}';
      } else {
        raw = 'unknown-device';
      }
      return sha256.convert(utf8.encode(raw)).toString();
    } catch (_) {
      return 'unresolved-fingerprint';
    }
  }
}
