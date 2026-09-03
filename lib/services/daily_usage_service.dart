import 'package:shared_preferences/shared_preferences.dart';

/// Tracks daily usage of free-tier features.
/// Standard activation (no online/wifi code) gets:
///   - Online Challenge: 1 free match per day
///   - WiFi Challenge:   2 free matches per day (minimum 30 questions, no full setup)
class DailyUsageService {
  static const _keyOnlineDate  = 'daily_online_date';
  static const _keyOnlineCount = 'daily_online_count';
  static const _keyWifiDate    = 'daily_wifi_date';
  static const _keyWifiCount   = 'daily_wifi_count';

  static const int freeOnlinePerDay = 1;
  static const int freeWifiPerDay   = 2;

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2,'0')}-${n.day.toString().padLeft(2,'0')}';
  }

  static Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  // ── Online Challenge ───────────────────────────────────────────────────────

  static Future<int> getOnlineUsedToday() async {
    final p = await _p;
    final date = p.getString(_keyOnlineDate) ?? '';
    if (date != _today()) return 0;
    return p.getInt(_keyOnlineCount) ?? 0;
  }

  static Future<bool> canUseOnlineFree() async {
    return (await getOnlineUsedToday()) < freeOnlinePerDay;
  }

  static Future<void> recordOnlineUsage() async {
    final p = await _p;
    final today = _today();
    final stored = p.getString(_keyOnlineDate) ?? '';
    final count  = stored == today ? (p.getInt(_keyOnlineCount) ?? 0) : 0;
    await p.setString(_keyOnlineDate, today);
    await p.setInt(_keyOnlineCount, count + 1);
  }

  static Future<int> onlineRemainingToday() async {
    final used = await getOnlineUsedToday();
    return (freeOnlinePerDay - used).clamp(0, freeOnlinePerDay);
  }

  // ── WiFi Challenge ─────────────────────────────────────────────────────────

  static Future<int> getWifiUsedToday() async {
    final p = await _p;
    final date = p.getString(_keyWifiDate) ?? '';
    if (date != _today()) return 0;
    return p.getInt(_keyWifiCount) ?? 0;
  }

  static Future<bool> canUseWifiFree() async {
    return (await getWifiUsedToday()) < freeWifiPerDay;
  }

  static Future<void> recordWifiUsage() async {
    final p = await _p;
    final today = _today();
    final stored = p.getString(_keyWifiDate) ?? '';
    final count  = stored == today ? (p.getInt(_keyWifiCount) ?? 0) : 0;
    await p.setString(_keyWifiDate, today);
    await p.setInt(_keyWifiCount, count + 1);
  }

  static Future<int> wifiRemainingToday() async {
    final used = await getWifiUsedToday();
    return (freeWifiPerDay - used).clamp(0, freeWifiPerDay);
  }

  // ── Summary for home screen ────────────────────────────────────────────────
  static Future<Map<String, int>> getFreeTierSummary() async {
    return {
      'onlineRemaining': await onlineRemainingToday(),
      'wifiRemaining':   await wifiRemainingToday(),
    };
  }
}
