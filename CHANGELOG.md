# Changelog

## Unreleased

- `ReachBell.reset()` for logout: calls `POST /subscribers/unidentify` for the registered token (best effort), then forgets it.
- `register()` sends `previousToken` (the token from the last successful `register()`, or the new `previousToken` argument) when the token changed, so ReachBell carries tags and the external id over to the rotated token.
- `register()` and `reset()` run one at a time, and `FirebaseTokenSource.requestPermission()` no longer prompts when permission is already granted.
- Re-calling `init()` no longer closes the owned `http.Client` under requests that are still running.
- Every transport failure, including `Error`s, is reported as `ReachBellException`; NestJS array-style `message` fields are joined into the exception message.
- README: token-refresh note updated for the automatic carry-over, `reset()` on logout, and the `firebase_messaging` dependency and imports for the example.

## 1.0.0

- Initial release.
- `ReachBell.init` with `apiKey`, optional `apiUrl` and `timeout` (default 15 seconds).
- `ReachBell.register` obtains the FCM token through `firebase_messaging` on Android and iOS and registers the device, optionally linking an `externalId`.
- `ReachBell.identify`, `ReachBell.tag` and `ReachBell.untag` for the registered device.
- `ReachBellException` with `message`, `statusCode` and `body`.
