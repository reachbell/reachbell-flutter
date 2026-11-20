import 'package:flutter/foundation.dart';

import '../types/push_platform.dart';
import '../types/reachbell_exception.dart';

PushPlatform detectPushPlatform() {
  if (kIsWeb) {
    throw const ReachBellException(
        'ReachBell Flutter SDK supports Android and iOS only; use the browser SDK on the web');
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return PushPlatform.android;
    case TargetPlatform.iOS:
      return PushPlatform.ios;
    default:
      throw ReachBellException(
          'Unsupported platform: ${defaultTargetPlatform.name}; ReachBell supports Android and iOS');
  }
}
