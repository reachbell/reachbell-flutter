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

  @override
  Future<bool> requestPermission() async {
    final settings = await _instance.requestPermission();
    final status = settings.authorizationStatus;
    return status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> getToken(PushPlatform platform) async {
    if (platform == PushPlatform.ios) {
      await _waitForApnsToken();
    }
    // ignore: deprecated_member_use
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
