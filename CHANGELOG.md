# Changelog

## Unreleased

- `ReachBell.reset()` for logout: calls `POST /subscribers/unidentify` for the registered token (best effort), then forgets it.
- `register()` sends `previousToken` (the token from the last successful `register()`, or the new `previousToken` argument) when the token changed, so ReachBell carries tags and the external id over to the rotated token.
- `register()` and `reset()` run one at a time, and `FirebaseTokenSource.requestPermission()` no longer prompts when permission is already granted.
- After `reset()`, the first `register()` without an `externalId` sends `"externalId": null`, so a logout whose unidentify failed offline is repaired. The flag lives in memory and is cleared after a successful `register()`.
- `identify()`, `tag()` and `untag()` run on the same queue as `register()` and `reset()`, so `reset(); register(); identify('u2');` without `await` keeps that order. `identify()` right after `reset()` with no `register()` in between still throws, because `reset()` forgets the token.
- `register()` sends `os` (`Android` / `iOS`), `osVersion` on iOS (from `Platform.operatingSystemVersion`; omitted on Android, where that value is a kernel string and the release would need a plugin) and `device` (`mobile`, or `tablet` when the physical display's shortest side is at least 600 logical pixels, falling back to the window when no display size is reported), like the Android and iOS SDKs, so subscribers are no longer recorded as `Unknown` / `desktop`. `dart:io` is imported conditionally, so the package still compiles for the web.
- `init(tokenTimeout:)` (default 30 seconds) bounds `requestPermission()` and `getToken()` in `register()`. A call that does not complete in time throws `ReachBellException` and the queue moves on.
- README: delete a persisted token on `reset()`.
- Re-calling `init()` no longer closes the owned `http.Client` under requests that are still running.
- Every transport failure, including `Error`s, is reported as `ReachBellException`; NestJS array-style `message` fields are joined into the exception message.
- README: token-refresh note updated for the automatic carry-over, `reset()` on logout, and the `firebase_messaging` dependency and imports for the example.

## 1.0.0

- Initial release.
- `ReachBell.init` with `apiKey`, optional `apiUrl` and `timeout` (default 15 seconds).
- `ReachBell.register` obtains the FCM token through `firebase_messaging` on Android and iOS and registers the device, optionally linking an `externalId`.
- `ReachBell.identify`, `ReachBell.tag` and `ReachBell.untag` for the registered device.
- `ReachBellException` with `message`, `statusCode` and `body`.
