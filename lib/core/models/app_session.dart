class AppSession {
  final String accessToken;
  final String refreshToken;
  final String role;
  final String email;
  final String userId;

  const AppSession({
    required this.accessToken,
    required this.refreshToken,
    required this.role,
    required this.email,
    required this.userId,
  });
}
