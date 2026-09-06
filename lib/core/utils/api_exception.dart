class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String code;

  ApiException({
    required this.statusCode,
    required this.message,
    required this.code,
  });

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}
