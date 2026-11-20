# Changelog

## 1.0.0

- Initial release.
- `ReachBell.init` with `apiKey`, optional `apiUrl` and `timeout` (default 15 seconds).
- `ReachBell.register` obtains the FCM token through `firebase_messaging` on Android and iOS and registers the device, optionally linking an `externalId`.
- `ReachBell.identify`, `ReachBell.tag` and `ReachBell.untag` for the registered device.
- `ReachBellException` with `message`, `statusCode` and `body`.
