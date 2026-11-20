import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'constants/api.dart';
import 'helpers/api_client.dart';
import 'helpers/token_source.dart';
import 'types/config.dart';
import 'types/push_platform.dart';
import 'types/reachbell_exception.dart';
import 'types/register_result.dart';
import 'types/token_type.dart';
import 'utils/platform.dart';
import 'utils/url.dart';

class ReachBell {
  ReachBell._();

  static ReachBellConfig? _config;
  static ApiClient? _api;
  static http.Client? _ownedClient;
  static String? _token;

  static http.Client? _testClient;
  static TokenSource? _testTokenSource;
  static PushPlatform? _testPlatform;

  static String? get token => _token;

  static bool get isInitialized => _config != null;

  static void init({
    required String apiKey,
    String? apiUrl,
    Duration timeout = defaultTimeout,
  }) {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw const ReachBellException('ReachBell.init: apiKey is required');
    }
    if (timeout <= Duration.zero) {
      throw const ReachBellException(
          'ReachBell.init: timeout must be greater than zero');
    }
    final url = normalizeApiUrl(apiUrl ?? defaultApiUrl);
    if (Uri.tryParse(url)?.hasScheme != true) {
      throw ReachBellException('ReachBell.init: invalid apiUrl "$apiUrl"');
    }
    final config = ReachBellConfig(apiKey: key, apiUrl: url, timeout: timeout);
    _ownedClient?.close();
    _ownedClient = null;
    final client = _testClient ?? (_ownedClient = http.Client());
    _config = config;
    _api = ApiClient(config, client);
  }

  static Future<RegisterResult> register({String? externalId}) async {
    final api = _requireApi('register');
    final platform = _testPlatform ?? detectPushPlatform();
    final source = _testTokenSource ?? FirebaseTokenSource();

    final bool granted;
    try {
      granted = await source.requestPermission();
    } on ReachBellException {
      rethrow;
    } catch (error) {
      throw ReachBellException(
          'Failed to request notification permission: $error');
    }
    if (!granted) {
      throw const ReachBellException('Notification permission denied');
    }

    final String? deviceToken;
    try {
      deviceToken = await source.getToken(platform);
    } on ReachBellException {
      rethrow;
    } catch (error) {
      throw ReachBellException('Failed to obtain a push token: $error');
    }
    if (deviceToken == null || deviceToken.isEmpty) {
      throw const ReachBellException('No push token could be obtained');
    }

    const tokenType = TokenType.fcm;
    final body = <String, Object?>{
      'token': deviceToken,
      'tokenType': tokenType.value,
      'platform': platform.value,
    };
    final id = externalId?.trim();
    if (id != null && id.isNotEmpty) {
      body['externalId'] = id;
    }

    final response = await api.post(subscribersPath, body);
    _token = deviceToken;

    return RegisterResult(
      token: deviceToken,
      tokenType: tokenType,
      platform: platform,
      subscriberId: _subscriberId(response.body),
    );
  }

  static Future<void> identify(String externalId) async {
    final api = _requireApi('identify');
    final token = _requireToken('identify');
    final id = externalId.trim();
    if (id.isEmpty) {
      throw const ReachBellException('identify: externalId is required');
    }
    await api.postAction(identifyPath, {'token': token, 'externalId': id});
  }

  static Future<void> tag(List<String> tags) =>
      _tagAction('tag', tagPath, tags);

  static Future<void> untag(List<String> tags) =>
      _tagAction('untag', untagPath, tags);

  static Future<void> _tagAction(
      String method, String path, List<String> tags) async {
    final api = _requireApi(method);
    final token = _requireToken(method);
    final cleaned = tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
    if (cleaned.isEmpty) {
      throw ReachBellException('$method: at least one tag is required');
    }
    await api.postAction(path, {'token': token, 'tags': cleaned});
  }

  static ApiClient _requireApi(String method) {
    final api = _api;
    if (api == null) {
      throw ReachBellException(
          'ReachBell.init() must be called before $method()');
    }
    return api;
  }

  static String _requireToken(String method) {
    final token = _token;
    if (token == null) {
      throw ReachBellException(
          'ReachBell.register() must succeed before $method()');
    }
    return token;
  }

  static String? _subscriberId(Object? body) {
    if (body is! Map) return null;
    final direct = body['_id'] ?? body['id'] ?? body['subscriberId'];
    if (direct is String && direct.isNotEmpty) return direct;
    final nested = body['subscriber'] ?? body['data'];
    if (nested is Map) {
      final value = nested['_id'] ?? nested['id'];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  @visibleForTesting
  static void debugOverride({
    http.Client? httpClient,
    TokenSource? tokenSource,
    PushPlatform? platform,
  }) {
    _testClient = httpClient;
    _testTokenSource = tokenSource;
    _testPlatform = platform;
  }

  @visibleForTesting
  static void debugReset() {
    _ownedClient?.close();
    _ownedClient = null;
    _config = null;
    _api = null;
    _token = null;
    _testClient = null;
    _testTokenSource = null;
    _testPlatform = null;
  }
}
