class ReachBellConfig {
  const ReachBellConfig({
    required this.apiKey,
    required this.apiUrl,
    required this.timeout,
    this.tokenTimeout = const Duration(seconds: 30),
  });

  final String apiKey;
  final String apiUrl;
  final Duration timeout;

  /// Upper bound for the notification permission request and for reading the
  /// FCM token in register().
  final Duration tokenTimeout;
}
