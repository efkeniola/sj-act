import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Manages the one-time, 24-hour Free Trial add-on and the always-on
/// base Free Plan limits. This is separate from paid activation, which
/// lives in [ActivationService] — that always wins when active.
///
/// ── Free Plan (no purchase, no trial needed — always available) ─────────
///   • Full Practice Exam: Set 1 only, ONE attempt ever.
///   • Section Practice: English & Math only, unlimited. Reading & Science
///     are locked behind Standard activation (unchanged from before).
///   • Question Sets 2 and 3 are locked everywhere behind Standard
///     activation.
///   • Online Challenge / WiFi Challenge: locked (see DailyUsageService
///     for the Standard package's daily-free-match rules).
///   • Leaderboard: locked.
///
/// ── Free Trial (opt-in, one-time, 24 hours from the moment the user
///    taps "Start Free Trial") ─────────────────────────────────────────────
///   • Full Practice Exam Set 1 becomes UNLIMITED for the 24-hour window
///     (the "once ever" cap is suspended, not consumed/reset — it resumes
///     the instant the trial window closes).
///   • Online Challenge: ONE trial match, HOST ONLY, capped at 20
///     questions.
///   • WiFi Challenge: ONE trial match as HOST and ONE as JOIN (so two
///     total, one of each), each capped at 20 questions.
///   • Leaderboard: unlocked for the duration of the trial.
///   Once 24 hours pass, everything reverts to the base Free Plan
///   automatically — this is a pure local-timestamp check, no server
///   round-trip, so it can't get "stuck" unlocked.
///
/// A user who buys/redeems an activation code — including *during* an
/// active trial — is unaffected by any of this: screens should always
/// check Standard/Online/WiFi activation status FIRST, and only fall back
/// to these free-plan/trial checks when the relevant activation is not
/// active. That check order is what makes switching from trial to a paid
/// package seamless with no double-gating or leftover restrictions.
class FreeTrialService {
  static const _kTrialStartedAt = 'trial_started_at';
  static const _kFreeExamUsed = 'free_exam_set1_used';
  static const _kOnlineTrialUsed = 'trial_online_used';
  static const _kWifiHostTrialUsed = 'trial_wifi_host_used';
  static const _kWifiJoinTrialUsed = 'trial_wifi_join_used';

  static const Duration trialDuration = Duration(hours: 24);
  static const int trialChallengeQuestionCount = 20;

  static Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  // ── Trial lifecycle ──────────────────────────────────────────────────────

  /// True once the user has ever tapped "Start Free Trial" (whether or not
  /// the 24-hour window is still open) — used to decide whether to show
  /// "Start Free Trial" vs. "Free trial used" on the home screen.
  static Future<bool> hasStartedTrial() async =>
      (await _p).containsKey(_kTrialStartedAt);

  static Future<DateTime?> trialStartedAt() async {
    final v = (await _p).getString(_kTrialStartedAt);
    return v == null ? null : DateTime.tryParse(v);
  }

  /// Starts the 24-hour trial. No-op (returns false) if it was already
  /// started before — the trial can only ever be used once per device,
  /// regardless of whether it has since expired.
  static Future<bool> startTrial() async {
    final p = await _p;
    if (p.containsKey(_kTrialStartedAt)) return false;
    await p.setString(_kTrialStartedAt, DateTime.now().toIso8601String());
    return true;
  }

  /// True only while inside the 24-hour window after starting the trial.
  static Future<bool> isTrialActive() async {
    final start = await trialStartedAt();
    if (start == null) return false;
    return DateTime.now().difference(start) < trialDuration;
  }

  /// True once the trial was started AND the 24 hours have elapsed.
  static Future<bool> isTrialExpired() async {
    final start = await trialStartedAt();
    if (start == null) return false;
    return DateTime.now().difference(start) >= trialDuration;
  }

  static Future<Duration> trialTimeRemaining() async {
    final start = await trialStartedAt();
    if (start == null) return Duration.zero;
    final remaining = trialDuration - DateTime.now().difference(start);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  // ── Free Plan: Full Exam Set 1 (one attempt ever, unless trial active) ──

  static Future<bool> hasUsedFreeFullExam() async =>
      (await _p).getBool(_kFreeExamUsed) ?? false;

  static Future<void> markFreeFullExamUsed() async =>
      (await _p).setBool(_kFreeExamUsed, true);

  /// Whether the user may START a Full Practice Exam on [setNumber] right
  /// now, given their [standardActive] status. Standard activation always
  /// unlocks every set with unlimited attempts; otherwise Set 1 is
  /// available once ever (or unlimited during an active trial), and Sets
  /// 2/3 are locked entirely until Standard activation.
  static Future<bool> canStartFullExam(int setNumber, {required bool standardActive}) async {
    if (standardActive) return true;
    if (setNumber != 1) return false;
    if (await isTrialActive()) return true;
    return !(await hasUsedFreeFullExam());
  }

  /// Call once after a Set-1 full exam is completed, to consume the one
  /// free-plan attempt. Safe to call unconditionally — it's a no-op for
  /// standard-activated users, other sets, and attempts taken during an
  /// active trial (trial attempts never burn the permanent free-plan slot).
  static Future<void> recordFullExamCompleted(int setNumber, {required bool standardActive}) async {
    if (standardActive || setNumber != 1) return;
    if (await isTrialActive()) return;
    await markFreeFullExamUsed();
  }

  // ── Free Plan: Section Practice (English & Math free; sets locked) ──────

  /// English & Math practice is always free; Reading & Science need
  /// Standard activation — the trial intentionally does NOT unlock these,
  /// matching the app's existing "why locked" product rule.
  static bool isSectionFreeToPractice(ActSection section) =>
      section == ActSection.english || section == ActSection.math;

  /// Only Set 1 is available without Standard activation, for any section.
  static bool isSetFreeToPractice(int setNumber) => setNumber == 1;

  // ── Trial: Online Challenge (host-only, 20 questions, once) ─────────────

  static Future<bool> hasUsedOnlineTrial() async =>
      (await _p).getBool(_kOnlineTrialUsed) ?? false;
  static Future<void> markOnlineTrialUsed() async =>
      (await _p).setBool(_kOnlineTrialUsed, true);

  static Future<bool> canUseOnlineTrial() async {
    if (!(await isTrialActive())) return false;
    return !(await hasUsedOnlineTrial());
  }

  // ── Trial: WiFi Challenge (host OR join, 20 questions, once each) ───────

  static Future<bool> hasUsedWifiHostTrial() async =>
      (await _p).getBool(_kWifiHostTrialUsed) ?? false;
  static Future<void> markWifiHostTrialUsed() async =>
      (await _p).setBool(_kWifiHostTrialUsed, true);

  static Future<bool> hasUsedWifiJoinTrial() async =>
      (await _p).getBool(_kWifiJoinTrialUsed) ?? false;
  static Future<void> markWifiJoinTrialUsed() async =>
      (await _p).setBool(_kWifiJoinTrialUsed, true);

  static Future<bool> canUseWifiHostTrial() async {
    if (!(await isTrialActive())) return false;
    return !(await hasUsedWifiHostTrial());
  }

  static Future<bool> canUseWifiJoinTrial() async {
    if (!(await isTrialActive())) return false;
    return !(await hasUsedWifiJoinTrial());
  }

  /// True if there's anything left to use in the challenge trial at all —
  /// drives whether the home screen still shows a "Trial" entry point for
  /// Online/WiFi Challenge cards.
  static Future<bool> hasAnyChallengeTrialLeft() async {
    if (!(await isTrialActive())) return false;
    final online = !(await hasUsedOnlineTrial());
    final wifiHost = !(await hasUsedWifiHostTrial());
    final wifiJoin = !(await hasUsedWifiJoinTrial());
    return online || wifiHost || wifiJoin;
  }

  // ── Leaderboard ───────────────────────────────────────────────────────────

  static Future<bool> canAccessLeaderboard({required bool standardActive}) async {
    if (standardActive) return true;
    return await isTrialActive();
  }

  // ── Debug / testing helper ───────────────────────────────────────────────
  // Not wired into any UI — intentionally left here only so QA can reset
  // trial state during testing without reinstalling the app.
  static Future<void> resetAllForTesting() async {
    final p = await _p;
    await p.remove(_kTrialStartedAt);
    await p.remove(_kFreeExamUsed);
    await p.remove(_kOnlineTrialUsed);
    await p.remove(_kWifiHostTrialUsed);
    await p.remove(_kWifiJoinTrialUsed);
  }
}
