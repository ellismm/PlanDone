class BoardPermissionDeniedException implements Exception {
  BoardPermissionDeniedException(this.message);

  final String message;

  @override
  String toString() => 'BoardPermissionDeniedException: $message';
}

class BoardValidationException implements Exception {
  BoardValidationException(this.message);

  final String message;

  @override
  String toString() => 'BoardValidationException: $message';
}
