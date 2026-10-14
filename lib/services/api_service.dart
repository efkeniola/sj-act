import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../utils/constants.dart';
import 'trusted_clock.dart';

/// Result of classifying a network failure.
class _NetFailure {
  final String message;
  final String headline;
  final bool clockProblem;
  const _NetFailure(this.message, this.headline, this.clockProblem);
}

/// Result wrapper — callers never need to handle raw exceptions.
class ApiResult<T> {
  final bool success;
  final T? data;
  final String? errorMessage;
  final bool wasTimeout;
  /// The SERVER's current time (from its `Date` header) when it sent one.
  /// Judge expiry with this — never with the phone's (changeable) date.
  final DateTime? serverTime;

  ApiResult.ok(this.data, {this.serverTime})
      : success = true,
        errorMessage = null,
        wasTimeout = false;

  ApiResult.fail(this.errorMessage, {this.wasTimeout = false})
      : success = false,
        data = null,
        serverTime = null;
}

/// Activation-only server calls.
/// Leaderboard, online challenge, and offline features never call this.
class ApiService {
  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        AppConstants.apiKeyHeader: AppConstants.apiKeyValue,
      };

  /// Reads the server's clock from the standard `Date` header
  /// (e.g. "Tue, 13 Oct 2026 21:04:05 GMT"). Null if absent/unreadable.
  static DateTime? _serverTimeOf(http.Response res) {
    try {
      final h = res.headers['date'];
      if (h == null) return null;
      final m = RegExp(r'(\d{1,2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2})').firstMatch(h);
      if (m == null) return null;
      const months = {
        'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
        'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
      };
      final mon = months[m.group(2)];
      if (mon == null) return null;
      final t = DateTime.utc(int.parse(m.group(3)!), mon, int.parse(m.group(1)!), int.parse(m.group(4)!),
          int.parse(m.group(5)!), int.parse(m.group(6)!));
      return t.year >= 2024 ? t : null; // ignore nonsense values
    } catch (_) {
      return null;
    }
  }

  static DateTime? _syncClock(http.Response res) {
    final t = _serverTimeOf(res);
    if (t != null) unawaited(TrustedClock.syncFromServer(t));
    return t;
  }

  static Future<ApiResult<Map<String, dynamic>>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final res = await http
          .post(
            Uri.parse('${AppConstants.baseApiUrl}$path'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(AppConstants.apiTimeout);

      final serverTime = _syncClock(res);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return ApiResult.ok(jsonDecode(res.body) as Map<String, dynamic>, serverTime: serverTime);
      }
      final decoded = _safeDecode(res.body);
      return ApiResult.fail(
        decoded?['message']?.toString() ??
            'Request failed (${res.statusCode}). Please try again.',
      );
    } on TimeoutException {
      return ApiResult.fail(
        'The server took too long to respond. Check your connection and try again.',
        wasTimeout: true,
      );
    } catch (e) {
      return ApiResult.fail(_describeError(e));
    }
  }

  static Future<ApiResult<Map<String, dynamic>>> get(String path) async {
    try {
      final res = await http
          .get(Uri.parse('${AppConstants.baseApiUrl}$path'), headers: _headers)
          .timeout(AppConstants.apiTimeout);

      final serverTime = _syncClock(res);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return ApiResult.ok(jsonDecode(res.body) as Map<String, dynamic>, serverTime: serverTime);
      }
      final decoded = _safeDecode(res.body);
      return ApiResult.fail(
        decoded?['message']?.toString() ??
            'Request failed (${res.statusCode}). Please try again.',
      );
    } on TimeoutException {
      return ApiResult.fail(
        'The server took too long to respond. Check your connection and try again.',
        wasTimeout: true,
      );
    } catch (e) {
      return ApiResult.fail(_describeError(e));
    }
  }

  static Map<String, dynamic>? _safeDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ── Telling "no internet" apart from "wrong phone date" ────────────────
  // Phone dates outside this window are certainly wrong. Move the window
  // forward when you ship a much newer release.
  static final DateTime _plausibleFrom = DateTime.utc(2026, 1, 1);
  static final DateTime _plausibleTo = DateTime.utc(2029, 1, 1);

  /// No data / no WiFi / DNS failure / dropped connection.
  static bool _isOffline(Object e) {
    if (e is SocketException) return true;
    final s = e.toString().toUpperCase();
    return s.contains('SOCKETEXCEPTION') ||
        s.contains('FAILED HOST LOOKUP') ||
        s.contains('NETWORK IS UNREACHABLE') ||
        s.contains('NO ROUTE TO HOST') ||
        s.contains('CONNECTION REFUSED') ||
        s.contains('CONNECTION RESET') ||
        s.contains('CONNECTION ABORT') ||
        s.contains('CONNECTION CLOSED') ||
        s.contains('TERMINATED DURING HANDSHAKE'); // dropped mid-handshake = bad network, not bad date
  }

  /// The secure connection was refused because of the certificate. A wrong
  /// phone date is the usual cause (certificates are checked against the
  /// phone's clock), but a login-page WiFi or a blocking network can too.
  static bool _isCertError(Object e) {
    final s = e.toString().toUpperCase();
    if (s.contains('TERMINATED DURING HANDSHAKE')) return false;
    if (s.contains('CERTIFICATE_VERIFY_FAILED') ||
        s.contains('CERT_NOT_YET_VALID') ||
        s.contains('CERT_HAS_EXPIRED') ||
        s.contains('CERTIFICATE HAS EXPIRED') ||
        s.contains('NOT YET VALID')) {
      return true;
    }
    return e is HandshakeException || e is TlsException;
  }

  static bool _phoneDateImplausible() {
    final n = DateTime.now().toUtc();
    return n.isBefore(_plausibleFrom) || !n.isBefore(_plausibleTo);
  }

  static String _phoneDateText() {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final n = DateTime.now();
    final hh = n.hour.toString().padLeft(2, '0');
    final mm = n.minute.toString().padLeft(2, '0');
    return '${n.day} ${m[n.month - 1]} ${n.year}, $hh:$mm';
  }

  static const String noInternetMessage =
      "No internet connection. Turn on mobile data or WiFi, then try again.";

  static String _badClockMessage() =>
      "Your phone's date or time looks wrong (it shows ${_phoneDateText()}). A wrong date stops the secure "
      "connection to the server. Open Settings → Date & time, turn on \"Set automatically\" (or set the correct "
      "date and time), then try again.";

  static String _secureFailMessage() =>
      "A secure connection to the server couldn't be made. Your phone's date shows ${_phoneDateText()} — if that "
      "is wrong, fix it in Settings → Date & time (Set automatically). If it is right, you may be on a WiFi that "
      "needs a login or blocks the app — try another network.";

  /// Classifies a network failure. Null = not one of the cases above.
  static _NetFailure? _classify(Object e) {
    if (_isCertError(e)) {
      return _phoneDateImplausible()
          ? _NetFailure(_badClockMessage(), 'Check your phone date & time', true)
          : _NetFailure(_secureFailMessage(), 'Secure connection failed', false);
    }
    if (_isOffline(e)) return _NetFailure(noInternetMessage, 'No internet connection', false);
    return null;
  }

  /// Maps a raised exception to an accurate, distinct message instead of
  /// always blaming "check your internet connection" — that used to be a
  /// blanket `catch (_)` covering every possible failure (a real dropped
  /// connection, a TLS/certificate error, a malformed/non-JSON server
  /// response, a bad URL, etc.), so someone whose internet was genuinely
  /// fine but hit e.g. a certificate or server-response problem would be
  /// told to check their connection — the one thing that wasn't actually
  /// wrong, with no way to tell what really failed.
  static String _describeError(Object e) {
    final f = _classify(e);
    if (f != null) return f.message;
    if (e is SocketException) {
      return 'Could not reach the server. Please check your internet connection.';
    }
    if (e is http.ClientException) {
      // package:http v1.x wraps most low-level connection failures (DNS
      // resolution failure, connection refused/reset, no route to host)
      // as ClientException rather than a raw SocketException — this is
      // almost always a genuine reachability problem (the device/network
      // can't establish a connection to the server at all), so it gets
      // the same message as SocketException rather than the generic one.
      return 'Could not reach the server. Please check your internet connection.\n(${e.message})';
    }
    if (e is HandshakeException) {
      return _secureFailMessage();
    }
    if (e is FormatException) {
      return 'The server sent back an unexpected response. This usually isn\'t '
          'an internet connection problem — please try again or contact support if it persists.';
    }
    return 'Something went wrong reaching the server (${e.runtimeType}). '
        'This isn\'t necessarily an internet connection problem — please try again or contact support if it persists.';
  }
}
