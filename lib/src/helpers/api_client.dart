import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/api.dart';
import '../types/config.dart';
import '../types/reachbell_exception.dart';

class ApiClient {
  ApiClient(this._config, this._client, {bool ownsClient = false})
      : _ownsClient = ownsClient;

  final ReachBellConfig _config;
  final http.Client _client;
  final bool _ownsClient;

  int _inFlight = 0;
  bool _closeWhenIdle = false;
  bool _closed = false;

  /// Closes the owned http.Client once every request already started on it
  /// has finished, so a re-`init()` does not fail them with
  /// "Client is already closed". A client passed in from outside is left open.
  void closeWhenIdle() {
    _closeWhenIdle = true;
    _maybeClose();
  }

  void _maybeClose() {
    if (!_ownsClient || _closed || !_closeWhenIdle || _inFlight > 0) return;
    _closed = true;
    _client.close();
  }

  Future<({int statusCode, Object? body})> post(
      String path, Map<String, Object?> body) async {
    final uri = Uri.parse('${_config.apiUrl}$path');
    final http.Response response;
    _inFlight++;
    try {
      response = await _client
          .post(
            uri,
            headers: {
              'content-type': 'application/json',
              'accept': 'application/json',
              apiKeyHeader: _config.apiKey,
            },
            body: jsonEncode(body),
          )
          .timeout(_config.timeout);
    } on TimeoutException {
      throw ReachBellException(
          'Request to $path timed out after ${_config.timeout.inMilliseconds}ms');
    } catch (error) {
      // Not only Exceptions: an http.Client can also surface Errors
      // (ArgumentError, StateError, TypeError) that callers should see as
      // ReachBellException like every other failure.
      throw ReachBellException('Network error calling $path: $error');
    } finally {
      _inFlight--;
      _maybeClose();
    }

    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReachBellException(
        _errorMessage(decoded) ??
            'ReachBell API responded with ${response.statusCode}',
        statusCode: response.statusCode,
        body: decoded,
      );
    }
    return (statusCode: response.statusCode, body: decoded);
  }

  Future<void> postAction(String path, Map<String, Object?> body) async {
    final response = await post(path, body);
    final decoded = response.body;
    if (decoded is Map && decoded['success'] == false) {
      final reason = decoded['reason'];
      throw ReachBellException(
        reason is String && reason.isNotEmpty
            ? reason
            : 'ReachBell API rejected $path',
        statusCode: response.statusCode,
        body: decoded,
      );
    }
  }

  Object? _decode(String raw) {
    if (raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return raw;
    }
  }

  String? _errorMessage(Object? decoded) {
    if (decoded is Map) {
      for (final key in const ['message', 'error', 'reason']) {
        final value = decoded[key];
        if (value is String && value.isNotEmpty) return value;
        // NestJS validation errors send `message` as a list of strings.
        if (value is List) {
          final parts = value
              .map((item) => item?.toString() ?? '')
              .where((item) => item.isNotEmpty)
              .toList();
          if (parts.isNotEmpty) return parts.join('; ');
        }
      }
    }
    return null;
  }
}
