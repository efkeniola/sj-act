import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Tracks daily usage of free-tier features.
/// Standard activation (no online/wifi code) gets:
///   - Online Challenge: 1 free match per day
///   - WiFi Challenge:   2 free matches per day (minimum 30 questions, no full setup)
///
/// The 2nd WiFi Challenge match of the day isn't free-free: after the 1st
/// match is used, starting the 2nd requires answering one random gate
/// question correctly. Getting it wrong doesn't necessarily end the day —
/// there's a 50% chance of one immediate retry attempt; if that's also
/// wrong (or the coin flip didn't grant a retry), the 2nd match is locked
/// until the next day. This class only tracks the *state* of that gate;
/// the actual question is chosen and shown by the caller (home screen),
/// which then reports the outcome via [recordWifiGateAnswer].
class DailyUsageService {
  static const _keyOnlineDate  = 'daily_online_date';
  static const _keyOnlineCount = 'daily_online_count';
  static const _keyWifiDate    = 'daily_wifi_date';
  static const _keyWifiCount   = 'daily_wifi_count';
  static const _keyWifiGateDate      = 'daily_wifi_gate_date';
  static const _keyWifiGateState     = 'daily_wifi_gate_state'; // 'none' | 'unlocked' | 'blocked_for_today'
  static const _keyWifiGateRetryUsed = 'daily_wifi_gate_retry_used';

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

  // ── WiFi Challenge: 2nd-match gate question ─────────────────────────────

  static Future<String> _wifiGateStateToday() async {
    final p = await _p;
    final date = p.getString(_keyWifiGateDate) ?? '';
    if (date != _today()) return 'none';
    return p.getString(_keyWifiGateState) ?? 'none';
  }

  /// Whether the 2nd WiFi Challenge match today needs the gate question
  /// answered first: true only when the 1st free match has already been
  /// used today, the 2nd hasn't been unlocked yet, and it isn't already
  /// blocked for today.
  static Future<bool> needsWifiGateForSecondMatch() async {
    final used = await getWifiUsedToday();
    if (used < 1 || used >= freeWifiPerDay) return false;
    final state = await _wifiGateStateToday();
    return state != 'unlocked' && state != 'blocked_for_today';
  }

  static Future<bool> isWifiSecondMatchBlockedForToday() async {
    return (await _wifiGateStateToday()) == 'blocked_for_today';
  }

  /// Records the outcome of answering the gate question and returns
  /// whether the 2nd WiFi Challenge slot is now unlocked for today.
  ///
  /// Wrong answer → 50/50 chance of one immediate retry (state stays
  /// 'none', so [needsWifiGateForSecondMatch] is still true and the caller
  /// can show the gate question again right away) vs. being locked out
  /// until tomorrow ('blocked_for_today'). Only one retry is ever granted
  /// per day — a wrong answer on the retry itself always locks for today,
  /// regardless of another coin flip, so this can't loop forever.
  static Future<bool> recordWifiGateAnswer({required bool correct}) async {
    final p = await _p;
    final today = _today();
    if (correct) {
      await p.setString(_keyWifiGateDate, today);
      await p.setString(_keyWifiGateState, 'unlocked');
      return true;
    }
    final sameDay = (p.getString(_keyWifiGateDate) ?? '') == today;
    final retryAlreadyUsed = sameDay && (p.getBool(_keyWifiGateRetryUsed) ?? false);
    await p.setString(_keyWifiGateDate, today);
    if (retryAlreadyUsed) {
      await p.setString(_keyWifiGateState, 'blocked_for_today');
      return false;
    }
    final getsRetry = Random().nextBool(); // 50% chance
    await p.setBool(_keyWifiGateRetryUsed, true);
    await p.setString(_keyWifiGateState, getsRetry ? 'none' : 'blocked_for_today');
    return false;
  }

  // ── Summary for home screen ────────────────────────────────────────────────
  static Future<Map<String, int>> getFreeTierSummary() async {
    return {
      'onlineRemaining': await onlineRemainingToday(),
      'wifiRemaining':   await wifiRemainingToday(),
    };
  }
}
