const String defaultApiUrl = 'https://api.reachbell.com';
const Duration defaultTimeout = Duration(seconds: 15);

/// Permission prompt and FCM token fetch, like Android's tokenFetchTimeoutMs.
const Duration defaultTokenTimeout = Duration(seconds: 30);
const String apiKeyHeader = 'x-api-key';

const String subscribersPath = '/subscribers';
const String identifyPath = '/subscribers/identify';
const String unidentifyPath = '/subscribers/unidentify';
const String tagPath = '/subscribers/tag';
const String untagPath = '/subscribers/untag';

const int apnsTokenAttempts = 10;
const Duration apnsTokenInterval = Duration(milliseconds: 500);
