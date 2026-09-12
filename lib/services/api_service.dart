import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../utils/constants.dart';

/// Result wrapper — callers never need to handle raw exceptions.
class ApiResult<T> {
  final bool success;
  final T? data;
  final String? errorMessage;
  final bool wasTimeout;

  ApiResult.ok(this.data)
      : success = true,
        errorMessage = null,
        wasTimeout = false;

  ApiResult.fail(this.errorMessage, {this.wasTimeout = false})
      : success = false,
        data = null;
}

/// Activation-only server calls.
/// Leaderboard, online challenge, and offline features never call this.
class ApiService {
  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        AppConstants.apiKeyHeader: AppConstants.apiKeyValue,
      };

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

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return ApiResult.ok(jsonDecode(res.body) as Map<String, dynamic>);
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

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return ApiResult.ok(jsonDecode(res.body) as Map<String, dynamic>);
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
