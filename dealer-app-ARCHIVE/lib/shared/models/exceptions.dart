class NetworkException implements Exception {
  final String message;
  NetworkException({required this.message});

  @override
  String toString() => message;
}

class AuthException implements Exception {
  final String message;
  AuthException({required this.message});

  @override
  String toString() => message;
}

class NotFoundException implements Exception {
  final String message;
  NotFoundException({required this.message});

  @override
  String toString() => message;
}

class ValidationException implements Exception {
  final String message;
  ValidationException({required this.message});

  @override
  String toString() => message;
}

class ApiException implements Exception {
  final String message;
  ApiException({required this.message});

  @override
  String toString() => message;
}