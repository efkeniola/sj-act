import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../models/models.dart';
import '../utils/constants.dart';
import 'api_service.dart';
import 'database_service.dart';
import 'device_service.dart';
import 'trusted_clock.dart';
import 'user_profile_service.dart';

enum ActivationOutcome {
  success,
  alreadyUsedElsewhere,
  invalidCode,
  offlineGraceValid,
  failed,
  timeout,
}

class ActivationResult {
  final ActivationOutcome outcome;
  final ActivationRecord? record;
  final String message;
  ActivationResult(this.outcome, this.record, this.message);
}

/// Handles all three ACT categories independently:
///   standard, online_challenge, wifi_challenge
/// A single "all" code unlocks all three simultaneously.
class ActivationService {
  static int graceDaysFor(String category) => AppConstants.challengeGraceDays;

  static bool isValidCodeFormat(String code) {
    return AppConstants.codePattern.hasMatch(code.trim().toUpperCase());
  }

  /// Tamper-detection signature: HMAC-style hash of record core fields.
  static String _sign(ActivationRecord r) {
    final raw =
        '${r.category}|${r.code}|${r.deviceId}|${r.expiresAt.toIso8601String()}|${r.graceEndsAt.toIso8601String()}|${AppConstants.apiKeyValue}';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  /// Redeem a code. One code may unlock multiple categories at once
  /// (e.g. an "all" code unlocks standard + online_challenge + wifi_challenge).
  static Future<ActivationResult> redeem({
    required String code,
    required UserProfile profile,
  }) async {
    final trimmed = code.trim().toUpperCase();
    if (!isValidCodeFormat(trimmed)) {
      return ActivationResult(
        ActivationOutcome.invalidCode,
        null,
        'That code format is not recognized. '
        'Standard codes start with SJACTS-, '
        'Online Challenge codes with SJACT-ONLINE-, '
        'WiFi Challenge codes with SJACT-WIFI-, '
        'and All Access codes with SJACT-ALL-.',
      );
    }
    if (!profile.isComplete) {
      return ActivationResult(
        ActivationOutcome.failed,
        null,
        'Please enter your full name, email, and phone number before activating.',
      );
    }
    if (!UserProfileService.isValidEmail(profile.email)) {
      return ActivationResult(ActivationOutcome.failed, null, 'Please enter a valid email address.');
    }
    if (!UserProfileService.isValidPhone(profile.phone)) {
      return ActivationResult(ActivationOutcome.failed, null, 'Please enter a valid phone number.');
    }

    final deviceId = await DeviceService.getDeviceId();
    final fingerprint = await DeviceService.getDeviceFingerprint();

    final result = await ApiService.post('/activate/', {
      'code': trimmed,
      'device_id': deviceId,
      'device_fingerprint': fingerprint,
      'full_name': profile.fullName.trim(),
      'email': profile.email.trim(),
      'phone': profile.phone.trim(),
    }).timeout(AppConstants.apiTimeout, onTimeout: () => ApiResult.fail('timeout', wasTimeout: true));

    await UserProfileService.saveProfile(profile);

    if (!result.success) {
      if (result.wasTimeout) {
        // This used to always check the 'standard' category's cache here,
        // regardless of which category the code being redeemed actually
        // belonged to — so a timed-out reactivation of, say, a WiFi
        // Challenge code could silently fall back to a completely
        // different category's (Standard's) cached record/expiry instead
        // of WiFi's own, which is exactly the kind of "wrong duration
        // showing" symptom this app has been fighting. Since this app's
        // single activation box doesn't know in advance which category a
        // code is for until the server tells us, check every category's
        // offline cache and use whichever one is still validly active —
        // never assume it must be 'standard'.
        for (final cat in [
          AppConstants.catStandard,
          AppConstants.catOnlineChallenge,
          AppConstants.catWifiChallenge,
        ]) {
          final cachedResult = await _cachedOfflineDetailed(cat);
          if (cachedResult.record != null) return cachedResult;
        }
        return ActivationResult(
          ActivationOutcome.timeout,
          null,
          'Could not reach the activation server. Please check your connection and try again.',
        );
      }
      if ((result.errorMessage ?? '').toLowerCase().contains('already been used')) {
        return ActivationResult(
          ActivationOutcome.alreadyUsedElsewhere,
          null,
          'This code has already been used on another device.',
        );
      }
      return ActivationResult(
        ActivationOutcome.failed,
        null,
        result.errorMessage ?? 'Activation failed. Please try again.',
      );
    }

    final data = result.data!;
    // Use the SERVER's activated_at (now present in every /activate/
    // response branch, including reactivation) instead of this device's
    // own clock. A local timestamp here is both inaccurate (device clocks
    // drift) and untrustworthy for something that timing logic depends
    // on — the server is the single source of truth for every other date
    // here (expiresAt), so activatedAt should be too.
    final DateTime expiresAt;
    final DateTime now;
    final List<String> categories;
    try {
      expiresAt = DateTime.parse(data['expires_at'] as String);
      now = data['activated_at'] != null
          ? DateTime.parse(data['activated_at'] as String)
          : (result.serverTime ?? await TrustedClock.now());
      categories = (data['categories'] as List?)?.cast<String>() ?? ['standard'];
    } catch (_) {
      return ActivationResult(
        ActivationOutcome.failed,
        null,
        'Something went wrong: the server sent back an unexpected reply, so the code could not be activated. '
        'Please try again.',
      );
    }

    // An EXPIRED code must never activate anything and is never stored.
    // Judged against the SERVER's time, not the phone's date, so a wrong or
    // changed phone date can neither reject a valid code nor accept an
    // expired one. (Grace is only for people who were already active.)
    final serverNow = result.serverTime ?? await TrustedClock.now();
    if (!expiresAt.isAfter(serverNow)) {
      return ActivationResult(
        ActivationOutcome.failed,
        null,
        'This code has expired (expired ${_fmtDate(expiresAt)}). Please use a valid code.',
      );
    }

    // Cache an activation record for each unlocked category
    ActivationRecord? firstRecord;
    for (final cat in categories) {
      final graceDays = graceDaysFor(cat);
      final graceEndsAt = expiresAt.add(Duration(days: graceDays));
      final record = ActivationRecord(
        category: cat,
        code: trimmed,
        deviceId: deviceId,
        activatedAt: now,
        expiresAt: expiresAt,
        graceEndsAt: graceEndsAt,
        duration: data['duration'] as String? ?? '6m',
      );
      await DatabaseService.instance.cacheActivation(record, _sign(record));
      firstRecord ??= record;
    }

    final catCount = categories.length;
    final catLabel = catCount == 1
        ? _categoryLabel(categories.first)
        : (catCount >= 3 ? 'All Access' : categories.map(_categoryLabel).join(' + '));

    return ActivationResult(
      ActivationOutcome.success,
      firstRecord,
      'Activation successful. $catLabel unlocked.',
    );
  }

  static String _fmtDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final l = d.toLocal();
    return '${months[l.month - 1]} ${l.day}, ${l.year}';
  }

  static String _categoryLabel(String cat) {
    switch (cat) {
      case 'online_challenge': return 'Online Challenge';
      case 'wifi_challenge': return 'WiFi Challenge';
      default: return 'Standard';
    }
  }

  static Future<ActivationResult> _cachedOfflineDetailed(String category) async {
    // The TRUSTED clock is server-corrected and can never go backwards; it
    // flags a phone date that was moved back (or its own data edited) until
    // the app next reaches the server.
    await TrustedClock.now();
    final clockOk = !TrustedClock.clockSuspicious;
    if (!clockOk) {
      return ActivationResult(
        ActivationOutcome.failed,
        null,
        'Your device clock appears to have been changed. Please reconnect to verify your activation.',
      );
    }

    final row = await DatabaseService.instance.getCachedActivation(category);
    if (row == null) {
      return ActivationResult(ActivationOutcome.failed, null, 'No previous activation found.');
    }

    final ActivationRecord record;
    try {
      record = ActivationRecord.fromMap(row);
    } catch (_) {
      await DatabaseService.instance.deleteCachedActivation(category);
      return ActivationResult(ActivationOutcome.failed, null, 'Your local activation data was damaged. Please re-enter your code.');
    }
    if (row['signature'] != _sign(record)) {
      // Edited on the phone → throw it away; the code has to be re-entered
      // (the server decides if it is still valid).
      await DatabaseService.instance.deleteCachedActivation(category);
      return ActivationResult(
        ActivationOutcome.failed,
        null,
        'Your local activation data could not be verified, so it was removed. Please re-enter your code.',
      );
    }
    // Device binding: a database copied/restored from another phone must not
    // work here.
    if (record.deviceId != await DeviceService.getDeviceId()) {
      return ActivationResult(
        ActivationOutcome.failed,
        null,
        'This activation belongs to a different device. Please re-enter your code on this device.',
      );
    }
    if (record.isExpired) {
      // Past expiry AND grace: delete it, so there is no stored date left to
      // "revive" by changing the phone date.
      await DatabaseService.instance.deleteCachedActivation(category);
      return ActivationResult(ActivationOutcome.failed, null, 'Your activation and grace period have both expired.');
    }
    return ActivationResult(
      ActivationOutcome.offlineGraceValid,
      record,
      'You are offline — using your last verified activation.',
    );
  }

  /// Check current status for a category — tries server first, falls back to cache.
  ///
  /// Intentionally NEVER auto-detects/auto-reactivates a previous
  /// activation on a fresh install. It only ever asks the server about a
  /// category if there's already a local cache record for it on THIS
  /// install (i.e. the user activated it, on this install, at some point).
  /// If there's no local record — e.g. right after a reinstall, when the
  /// app's local database has been wiped — this returns null immediately
  /// without contacting the server at all, even though the device ID
  /// itself may still resolve to the same value as before (device IDs can
  /// persist across a reinstall on some platforms). Two different people
  /// can end up resolving to the same device ID in edge cases, so that ID
  /// alone must never be trusted to silently restore someone's purchase —
  /// activation is only ever restored by the user explicitly re-entering
  /// their code (which redeem() handles as a normal, explicit reactivation).
  ///
  /// IMPORTANT — queried PER CATEGORY, one call per category, not as one
  /// bulk "give me every category's status" call. This used to call
  /// `/check-status/?device_id=...` once and read `data['categories'][category]`
  /// out of a single combined response. That shape made it possible for a
  /// stale/longer-lived record in one category (e.g. a 1-year WiFi
  /// Challenge activation) to leak into another category's status, or for
  /// a freshly-*reactivated* shorter code (e.g. a 1-month code replacing
  /// that 1-year one) to still show the old expiry, because the bulk
  /// endpoint doesn't guarantee it re-resolves every category's expiry
  /// independently on every call the way three isolated calls do. Each
  /// category now gets its own request and its own response, so a
  /// reactivation for one category can never be shadowed by another
  /// category's (or that same category's previous) expiry date.
  static Future<ActivationRecord?> getStatus(String category) async {
    final existingLocalRecord = await DatabaseService.instance.getCachedActivation(category);
    if (existingLocalRecord == null) return null;

    // Anchor the trusted clock before any expiry maths below.
    await TrustedClock.now();

    try {
      final deviceId = await DeviceService.getDeviceId();
      final result = await ApiService.get('/check-status/?category=$category&device_id=$deviceId')
          .timeout(AppConstants.apiTimeout);
      if (result.success && result.data != null) {
        final data = result.data!;
        if (data['active'] == true) {
          final expiresAt = DateTime.parse(data['expires_at'] as String);
          final graceEndsAt = expiresAt.add(Duration(days: graceDaysFor(category)));
          final record = ActivationRecord(
            category: category,
            code: data['code'] as String? ?? '',
            deviceId: deviceId,
            activatedAt: DateTime.parse(data['activated_at'] as String),
            expiresAt: expiresAt,
            graceEndsAt: graceEndsAt,
            duration: data['duration'] as String? ?? '6m',
          );
          await DatabaseService.instance.cacheActivation(record, _sign(record));
          return record;
        }
        // The server answered "not active". Keep the stored record ONLY while
        // it is genuinely in its grace window; if it is past grace (or was
        // revoked before its expiry) delete it so nothing is left to revive.
        try {
          final stored = ActivationRecord.fromMap(existingLocalRecord);
          if (!stored.isInGrace) {
            await DatabaseService.instance.deleteCachedActivation(category);
          }
        } catch (_) {
          await DatabaseService.instance.deleteCachedActivation(category);
        }
        return null;
      }
    } catch (_) {}

    final cached = await _cachedOfflineDetailed(category);
    return cached.record;
  }

  /// Deletes every stored activation that is past expiry + grace, edited, or
  /// damaged. Run at app start so an expired activation's dates are removed
  /// for good — after that, changing the phone date has nothing to revive.
  static Future<void> purgeExpired() async {
    try {
      await TrustedClock.now();
      for (final cat in [
        AppConstants.catStandard,
        AppConstants.catOnlineChallenge,
        AppConstants.catWifiChallenge,
      ]) {
        final row = await DatabaseService.instance.getCachedActivation(cat);
        if (row == null) continue;
        try {
          final record = ActivationRecord.fromMap(row);
          if (row['signature'] != _sign(record) || record.isExpired) {
            await DatabaseService.instance.deleteCachedActivation(cat);
          }
        } catch (_) {
          await DatabaseService.instance.deleteCachedActivation(cat);
        }
      }
    } catch (_) {}
  }

  /// Check all three categories at once.
  static Future<Map<String, ActivationRecord?>> getAllStatuses() async {
    final cats = [
      AppConstants.catStandard,
      AppConstants.catOnlineChallenge,
      AppConstants.catWifiChallenge,
    ];
    final result = <String, ActivationRecord?>{};
    for (final cat in cats) {
      result[cat] = await getStatus(cat);
    }
    return result;
  }
}
