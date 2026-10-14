import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../utils/constants.dart';
import 'trusted_clock.dart';

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

  /// Maps a raised exception to an accurate, distinct message instead of
  /// always blaming "check your internet connection" — that used to be a
  /// blanket `catch (_)` covering every possible failure (a real dropped
  /// connection, a TLS/certificate error, a malformed/non-JSON server
  /// response, a bad URL, etc.), so someone whose internet was genuinely
  /// fine but hit e.g. a certificate or server-response problem would be
  /// told to check their connection — the one thing that wasn't actually
  /// wrong, with no way to tell what really failed.
  static String _describeError(Object e) {
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
      return 'Secure connection to the server failed (certificate/TLS error). '
          'This isn\'t a connectivity issue — please try again or contact support if it persists.';
    }
    if (e is FormatException) {
      return 'The server sent back an unexpected response. This usually isn\'t '
          'an internet connection problem — please try again or contact support if it persists.';
    }
    return 'Something went wrong reaching the server (${e.runtimeType}). '
        'This isn\'t necessarily an internet connection problem — please try again or contact support if it persists.';
  }
}
