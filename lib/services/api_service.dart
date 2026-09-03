import 'dart:async';
import 'dart:convert';
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
    } catch (_) {
      return ApiResult.fail(
        'Could not reach the server. Please check your internet connection.',
      );
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
    } catch (_) {
      return ApiResult.fail(
        'Could not reach the server. Please check your internet connection.',
      );
    }
  }

  static Map<String, dynamic>? _safeDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
