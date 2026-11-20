class ReachBellConfig {
  const ReachBellConfig({
    required this.apiKey,
    required this.apiUrl,
    required this.timeout,
  });

  final String apiKey;
  final String apiUrl;
  final Duration timeout;
}
