# reachbell

Flutter client SDK for [ReachBell](https://reachbell.com) push notifications. It obtains the device push token through [`firebase_messaging`](https://pub.dev/packages/firebase_messaging), registers the device with ReachBell, and lets you link the subscription to your own user id and attach tags.

Sending pushes and building campaigns happen server-side with the ReachBell server SDKs. Full guide: [docs.reachbell.com/mobile/flutter](https://docs.reachbell.com/mobile/flutter).

## Install

```yaml
dependencies:
  firebase_core: ^3.0.0
  firebase_messaging: ^15.0.0
  reachbell: ^1.0.0
```

`reachbell` already depends on `firebase_messaging`; list it yourself as well when your code imports it, for example to listen to `onTokenRefresh` as shown below.

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
| `ReachBell.init({required String apiKey, String? apiUrl, Duration timeout, Duration tokenTimeout})` | Configure the SDK once. `apiUrl` defaults to `https://api.reachbell.com`, `timeout` (per API request) to 15 seconds. `tokenTimeout` (default 30 seconds) bounds the notification permission request and the FCM token read in `register()`. |
| `ReachBell.register({String? externalId, String? previousToken})` | Requests notification permission (skipped when already granted), reads the FCM token and registers the device. Calls run one at a time. When the token differs from the last registered one, `previousToken` defaults to that token. Returns a `RegisterResult`. |
| `ReachBell.identify(String externalId)` | Links the registered device to your user id. |
| `ReachBell.tag(List<String> tags)` | Adds tags to the registered subscriber. |
| `ReachBell.untag(List<String> tags)` | Removes tags from the registered subscriber. |
| `ReachBell.reset()` | Call on logout. Calls `POST /subscribers/unidentify` for the registered token (best effort, errors are ignored), then forgets the token. Waits for a `register()` in progress. |
| `ReachBell.token` | Token from the last successful `register()` in this process, or `null`. |

`RegisterResult` has `token`, `tokenType` (`TokenType.fcm` on both Android and iOS, since the token comes from Firebase Cloud Messaging), `platform` (`PushPlatform.android` or `PushPlatform.ios`) and `subscriberId`.

The token is kept in memory only. Registration is idempotent on the server, so call `register()` on every launch, and again from `FirebaseMessaging.instance.onTokenRefresh` when the token rotates. On a rotation, `register()` sends the previous token as `previousToken`, and ReachBell moves the old subscriber's tags and external id to the new token and deactivates the old one. You do not need to pass the external id again or re-apply tags:

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:reachbell/reachbell.dart';

void listenForTokenRefresh() {
  FirebaseMessaging.instance.onTokenRefresh.listen((_) async {
    try {
      await ReachBell.register();
    } on ReachBellException catch (e) {
      debugPrint('ReachBell re-register failed: ${e.message}');
    }
  });
}
```

Because the token lives in memory, a token that rotated while the app was not running is registered as a new subscriber on the next launch. If you persist `ReachBell.token` yourself, pass it back as `register(previousToken: savedToken)` to carry tags and the external id over in that case too. Delete that saved token when you call `ReachBell.reset()`: passed back after a logout, it would carry the old user's tags and external id over to the next registration.

When the user logs out, call `ReachBell.reset()` so the device is no longer linked to their user id. The device stays subscribed anonymously; call `register(externalId: ...)`, or `register()` followed by `identify(...)`, for the next user. The first `register()` after `reset()` without an `externalId` sends `"externalId": null`, so the server drops the old user even if the unidentify call failed offline. All SDK calls run one at a time in call order, so `reset()` followed by `register()` without `await` is safe. `reset()` forgets the token, so `identify()`, `tag()` and `untag()` throw `ReachBellException` until a `register()` after the reset succeeds. Queue them after that `register()` (calling them without `await` right after it is fine, since they wait for it), or pass the id as `register(externalId: ...)`.

```dart
Future<void> logout() async {
  await ReachBell.reset();
  // If you persist ReachBell.token, delete the saved copy here.
  // ...your own sign-out
}
```

## Errors

Every method except `reset()` throws `ReachBellException` with `message`, `statusCode` and `body`:

- `init()` not called, or `identify()` / `tag()` / `untag()` called before a successful `register()`.
- Notification permission denied, or no push token available. Also thrown when the permission request or the FCM token read takes longer than `tokenTimeout`; later calls are not held up by it.
- A non-2xx API response, for example `403` when the plan's subscriber limit is reached.
- A 2xx response with `success: false`, for example `subscriber_not_found`.
- A network failure or timeout, where `statusCode` is `null`.

## License

MIT
