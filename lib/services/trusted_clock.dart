import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../utils/constants.dart';
import 'device_service.dart';

/// "Now" that does NOT blindly trust the phone's date.
///
/// People change their phone date to cheat: roll it BACK to make an expired
/// code look valid / extend a trial, or push it to tomorrow to get another
/// "free round today". So every access decision uses this clock instead of
/// DateTime.now().
///
/// How it works
///  * Every reply from our server carries the server's real time. We store it
///    together with the phone's clock at that moment, so afterwards
///    trusted time = server time + (phone time now - phone time then).
///    A phone that was simply WRONG (hours or days off) is corrected for.
///  * We also remember the latest trusted time we have ever seen ("max
///    seen"). Trusted time can never go below it, so rolling the phone date
///    back gains nothing — and a rollback is flagged in [clockSuspicious].
///  * The stored values are signed; editing them makes the clock return a far
///    future date (everything locks) until the next server reply repairs it.
///  * Inside one app session time advances with a stopwatch, so changing the
///    date while the app is open has no effect either.
///
/// Honest limit: with NO internet at all there is no outside time source, so a
/// person who goes fully offline and keeps resetting the date to just after
/// their last session can slow expiry down. Any contact with the server fixes
/// the clock permanently, and the server stays the authority whenever online.
class TrustedClock {
  static const _key = 'sj_trusted_clock_v1';
  static const int _rollbackToleranceMs = 5 * 60 * 1000; // ignore small auto-time corrections
  static const int _writeEveryMs = 60 * 1000; // don't hammer secure storage

  static DateTime _base = DateTime.now();
  static final Stopwatch _sw = Stopwatch()..start();

  /// True when the last [now] call found the phone clock moved backwards
  /// (or the stored clock data tampered with) and nothing online has
  /// re-verified it yet.
  static bool clockSuspicious = false;

  /// True while paid access must stay PAUSED because the phone date was moved
  /// back (or the stored clock data was edited). Re-checks the clock every
  /// time, so it clears by itself the moment the user puts the date right
  /// (or the app next reaches the server). Nothing is deleted while paused.
  static Future<bool> isPaused() async {
    await now();
    return clockSuspicious;
  }

  /// Synchronous "now" for getters. It advances with a stopwatch from the
  /// last [now] / [syncFromServer], so it can't be rolled back mid-session.
  /// Call `await TrustedClock.now()` first (startup + every status check do).
  static DateTime get nowSync => _base.add(_sw.elapsed);

  static void _setBase(DateTime t) {
    _base = t;
    _sw
      ..reset()
      ..start();
  }

  static String _sig(int? s, int? p, int m) =>
      sha256.convert(utf8.encode('${s ?? 'x'}|${p ?? 'x'}|$m|${AppConstants.apiKeyValue}')).toString();

  static String _encode(int? s, int? p, int m) => jsonEncode({'s': s, 'p': p, 'm': m, 'g': _sig(s, p, m)});

  /// Trusted "now" (async: reads the stored anchor).
  static Future<DateTime> now() async {
    final phoneMs = DateTime.now().millisecondsSinceEpoch;
    int? s;
    int? p;
    int? maxMs;
    var tampered = false;

    final raw = await SecureStore.read(_key);
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        s = (m['s'] as num?)?.toInt();
        p = (m['p'] as num?)?.toInt();
        maxMs = (m['m'] as num).toInt();
        if (m['g'] != _sig(s, p, maxMs)) tampered = true;
      } catch (_) {
        tampered = true;
      }
    }

    if (tampered) {
      clockSuspicious = true;
      final far = DateTime.utc(2100);
      _setBase(far);
      return far;
    }

    // Phone clock corrected by how wrong it was at the last server contact.
    var tMs = (s != null && p != null) ? s + (phoneMs - p) : phoneMs;

    var suspicious = false;
    if (maxMs != null && tMs < maxMs) {
      suspicious = tMs < maxMs - _rollbackToleranceMs;
      tMs = maxMs; // never go backwards
    }
    clockSuspicious = suspicious;

    if (maxMs == null || tMs - maxMs > _writeEveryMs) {
      await SecureStore.write(_key, _encode(s, p, tMs));
    }

    final t = DateTime.fromMillisecondsSinceEpoch(tMs);
    _setBase(t);
    return t;
  }

  /// Called with the server's time from any server reply. The server is the
  /// authority, so this also repairs a suspicious / over-advanced clock.
  static Future<void> syncFromServer(DateTime serverTime) async {
    try {
      final sMs = serverTime.millisecondsSinceEpoch;
      final pMs = DateTime.now().millisecondsSinceEpoch;
      await SecureStore.write(_key, _encode(sMs, pMs, sMs));
      clockSuspicious = false;
      _setBase(serverTime.toLocal());
    } catch (_) {}
  }
}
