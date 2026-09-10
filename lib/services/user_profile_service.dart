import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'device_service.dart';

class UserProfileService {
  static Future<UserProfile?> getSavedProfile() async {
    final name = await SecureStore.read('sj_act_full_name');
    final email = await SecureStore.read('sj_act_email');
    final phone = await SecureStore.read('sj_act_phone');
    if (name == null && email == null && phone == null) return null;
    return UserProfile(fullName: name ?? '', email: email ?? '', phone: phone ?? '');
  }

  static Future<void> saveProfile(UserProfile profile) async {
    await SecureStore.write('sj_act_full_name', profile.fullName.trim());
    await SecureStore.write('sj_act_email', profile.email.trim());
    await SecureStore.write('sj_act_phone', profile.phone.trim());
  }

  static bool isValidEmail(String email) {
    return RegExp(r'^[\w\.\-\+]+@[\w\-]+\.[a-zA-Z]{2,}$').hasMatch(email.trim());
  }

  static bool isValidPhone(String phone) {
    final digitsOnly = phone.replaceAll(RegExp(r'[^\d]'), '');
    return RegExp(r'^[\d\s\+\-\(\)]+$').hasMatch(phone.trim()) &&
        digitsOnly.length >= 7 &&
        digitsOnly.length <= 15;
  }

  // ── Display name (in-app name, separate from contact profile) ────────────
  static const _displayNameKey = 'sj_act_display_name';

  static Future<String?> getDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_displayNameKey);
  }

  static Future<void> setDisplayName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayNameKey, name.trim());
  }

  // ── Online Challenge bet consequence: access pause ────────────────────────
  // When a player loses an "access paused" bet in the Online Challenge, entry
  // to Online Challenge is blocked until this timestamp.
  static const _onlineBetPauseKey = 'sj_act_online_bet_pause_until';

  static Future<DateTime?> getOnlineAccessPauseUntil() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_onlineBetPauseKey);
    if (ms == null) return null;
    final until = DateTime.fromMillisecondsSinceEpoch(ms);
    return until.isAfter(DateTime.now()) ? until : null;
  }

  static Future<void> setOnlineAccessPauseUntil(DateTime until) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_onlineBetPauseKey, until.millisecondsSinceEpoch);
  }

  static Future<void> clearOnlineAccessPause() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_onlineBetPauseKey);
  }

  // ── WiFi Challenge bet consequence: access pause ───────────────────────────
  // Kept separate from the Online Challenge pause above so losing a bet in
  // one mode never blocks the other.
  static const _wifiBetPauseKey = 'sj_act_wifi_bet_pause_until';

  static Future<DateTime?> getWifiAccessPauseUntil() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_wifiBetPauseKey);
    if (ms == null) return null;
    final until = DateTime.fromMillisecondsSinceEpoch(ms);
    return until.isAfter(DateTime.now()) ? until : null;
  }

  static Future<void> setWifiAccessPauseUntil(DateTime until) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_wifiBetPauseKey, until.millisecondsSinceEpoch);
  }

  static Future<void> clearWifiAccessPause() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_wifiBetPauseKey);
  }
}
