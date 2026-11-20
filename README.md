# reachbell

Flutter client SDK for [ReachBell](https://reachbell.com) push notifications. It obtains the device push token through [`firebase_messaging`](https://pub.dev/packages/firebase_messaging), registers the device with ReachBell, and lets you link the subscription to your own user id and attach tags.

Sending pushes and building campaigns happen server-side with the ReachBell server SDKs. Full guide: [docs.reachbell.com/mobile/flutter](https://docs.reachbell.com/mobile/flutter).

## Install

```yaml
dependencies:
  firebase_core: ^3.0.0
  reachbell: ^1.0.0
```

```bash
flutter pub get
```

## Firebase setup

ReachBell delivers Android and iOS push through Firebase Cloud Messaging, so you need a Firebase project:

1. Create a Firebase project and add your Android and iOS apps.
2. Run `flutterfire configure` to generate `lib/firebase_options.dart` and the native config files.
3. Android: add `<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />` to `AndroidManifest.xml` for Android 13+.
4. iOS: enable the Push Notifications and Background Modes (Remote notifications) capabilities, and upload your APNs auth key to the Firebase console. Push does not work on the iOS Simulator.

## Usage

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:reachbell/reachbell.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  ReachBell.init(apiKey: 'rb_live_your_public_key');
  runApp(const MyApp());
}
```

```dart
try {
  final result = await ReachBell.register(externalId: 'user_42');
  await ReachBell.identify('user_42');
  await ReachBell.tag(['pro', 'beta']);
  await ReachBell.untag(['beta']);
} on ReachBellException catch (e) {
  print('${e.statusCode}: ${e.message}');
}
```

## API

| Member | Description |
| --- | --- |
| `ReachBell.init({required String apiKey, String? apiUrl, Duration timeout})` | Configure the SDK once. `apiUrl` defaults to `https://api.reachbell.com`, `timeout` to 15 seconds. |
| `ReachBell.register({String? externalId})` | Requests notification permission, reads the FCM token and registers the device. Returns a `RegisterResult`. |
| `ReachBell.identify(String externalId)` | Links the registered device to your user id. |
| `ReachBell.tag(List<String> tags)` | Adds tags to the registered subscriber. |
| `ReachBell.untag(List<String> tags)` | Removes tags from the registered subscriber. |
| `ReachBell.token` | Token from the last successful `register()` in this process, or `null`. |

`RegisterResult` has `token`, `tokenType` (`TokenType.fcm` on both Android and iOS, since the token comes from Firebase Cloud Messaging), `platform` (`PushPlatform.android` or `PushPlatform.ios`) and `subscriberId`.

The token is kept in memory only. Registration is idempotent on the server, so call `register()` on every launch, and again from `FirebaseMessaging.instance.onTokenRefresh` when the token rotates.

## Errors

Every method throws `ReachBellException` with `message`, `statusCode` and `body`:

- `init()` not called, or `identify()` / `tag()` / `untag()` called before a successful `register()`.
- Notification permission denied, or no push token available.
- A non-2xx API response, for example `403` when the plan's subscriber limit is reached.
- A 2xx response with `success: false`, for example `subscriber_not_found`.
- A network failure or timeout, where `statusCode` is `null`.

## License

MIT
