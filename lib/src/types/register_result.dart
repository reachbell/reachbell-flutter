import 'push_platform.dart';
import 'token_type.dart';

class RegisterResult {
  const RegisterResult({
    required this.token,
    required this.tokenType,
    required this.platform,
    this.subscriberId,
  });

  final String token;
  final TokenType tokenType;
  final PushPlatform platform;
  final String? subscriberId;

  @override
  String toString() =>
      'RegisterResult(tokenType: ${tokenType.value}, platform: ${platform.value}, subscriberId: $subscriberId)';
}
