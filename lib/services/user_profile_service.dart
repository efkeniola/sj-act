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

  // ── Online Challenge bet consequence: practice required ───────────────────
  // When a player loses a "study_task" bet in the Online Challenge, they
  // must complete one practice section before they're allowed to start
  // another Online Challenge match.
  static const _onlineBetPracticeRequiredKey = 'sj_act_online_bet_practice_required';

  static Future<bool> getRequiresPracticeBeforeOnlineChallenge() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onlineBetPracticeRequiredKey) ?? false;
  }

  static Future<void> setRequiresPracticeBeforeOnlineChallenge(bool required) async {
    final prefs = await SharedPreferences.getInstance();
    if (required) {
      await prefs.setBool(_onlineBetPracticeRequiredKey, true);
    } else {
      await prefs.remove(_onlineBetPracticeRequiredKey);
    }
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

  // ── WiFi Challenge bet consequence: practice required ──────────────────────
  // Separate flag from the Online Challenge one above, for the same reason:
  // losing a "study_task" bet in one mode shouldn't block the other.
  static const _wifiBetPracticeRequiredKey = 'sj_act_wifi_bet_practice_required';

  static Future<bool> getRequiresPracticeBeforeWifiChallenge() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_wifiBetPracticeRequiredKey) ?? false;
  }

  static Future<void> setRequiresPracticeBeforeWifiChallenge(bool required) async {
    final prefs = await SharedPreferences.getInstance();
    if (required) {
      await prefs.setBool(_wifiBetPracticeRequiredKey, true);
    } else {
      await prefs.remove(_wifiBetPracticeRequiredKey);
    }
  }

  /// Clears whichever practice-required gate(s) are currently set, for both
  /// Online and WiFi Challenge. Called once a practice section is finished.
  static Future<void> clearAllPracticeRequiredGates() async {
    await setRequiresPracticeBeforeOnlineChallenge(false);
    await setRequiresPracticeBeforeWifiChallenge(false);
  }

  // ── Bet consequence: ranking points ledger ─────────────────────────────────
  // Shared between Online and WiFi Challenge "ranking points" bets — a
  // simple persistent zero-sum tally so winning/losing this bet type has a
  // real, visible, lasting effect instead of just flavor text.
  static const _betRankingPointsKey = 'sj_act_bet_ranking_points';

  static Future<int> getBetRankingPoints() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_betRankingPointsKey) ?? 0;
  }

  static Future<int> addBetRankingPoints(int delta) async {
    final prefs = await SharedPreferences.getInstance();
    final updated = (prefs.getInt(_betRankingPointsKey) ?? 0) + delta;
    await prefs.setInt(_betRankingPointsKey, updated);
    return updated;
  }

  // ── Bet consequence: Challenger badge forfeiture ───────────────────────────
  // Losing a "badge" bet suspends the player's own leaderboard rank badge
  // (gold/silver/bronze/top5/top10) for 24 hours, even if their score would
  // otherwise still earn one.
  static const _challengerBadgeSuspendedUntilKey = 'sj_act_challenger_badge_suspended_until';

  static Future<DateTime?> getChallengerBadgeSuspendedUntil() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_challengerBadgeSuspendedUntilKey);
    if (ms == null) return null;
    final until = DateTime.fromMillisecondsSinceEpoch(ms);
    return until.isAfter(DateTime.now()) ? until : null;
  }

  static Future<void> setChallengerBadgeSuspendedFor(Duration duration) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_challengerBadgeSuspendedUntilKey,
        DateTime.now().add(duration).millisecondsSinceEpoch);
  }

  // ── Bet consequence: "Top Challenger" bragging rights ──────────────────────
  // Winning a "bragging_rights" bet pins the winner's name as Top Challenger
  // for the remainder of the calendar day. Stored with the date it was set
  // so it naturally expires once the day rolls over — no timer needed.
  static const _topChallengerNameKey = 'sj_act_top_challenger_name';
  static const _topChallengerDateKey = 'sj_act_top_challenger_date';

  static String _todayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  static Future<String?> getTopChallengerToday() async {
    final prefs = await SharedPreferences.getInstance();
    final storedDate = prefs.getString(_topChallengerDateKey);
    if (storedDate != _todayKey(DateTime.now())) return null;
    return prefs.getString(_topChallengerNameKey);
  }

  static Future<void> setTopChallengerToday(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_topChallengerNameKey, name);
    await prefs.setString(_topChallengerDateKey, _todayKey(DateTime.now()));
  }
}
