import 'package:firebase_messaging/firebase_messaging.dart';

import '../constants/api.dart';
import '../types/push_platform.dart';

abstract class TokenSource {
  Future<bool> requestPermission();

  Future<String?> getToken(PushPlatform platform);
}

class FirebaseTokenSource implements TokenSource {
  FirebaseTokenSource([FirebaseMessaging? messaging]) : _messaging = messaging;

  final FirebaseMessaging? _messaging;

  FirebaseMessaging get _instance => _messaging ?? FirebaseMessaging.instance;

  /// Returns true straight away when permission is already granted, so
  /// repeated `register()` calls do not prompt again.
  @override
  Future<bool> requestPermission() async {
    final current = await _instance.getNotificationSettings();
    if (_isGranted(current.authorizationStatus)) return true;
    final settings = await _instance.requestPermission();
    return _isGranted(settings.authorizationStatus);
  }

  static bool _isGranted(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;

  @override
  Future<String?> getToken(PushPlatform platform) async {
    if (platform == PushPlatform.ios) {
      await _waitForApnsToken();
    }
    return _instance.getToken();
  }

  Future<void> _waitForApnsToken() async {
    for (var attempt = 0; attempt < apnsTokenAttempts; attempt++) {
      final apns = await _instance.getAPNSToken();
      if (apns != null) return;
      await Future<void>.delayed(apnsTokenInterval);
    }
  }
}
