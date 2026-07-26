/// A failure the interface can show without translating.
///
/// [message] is written for the person reading it: what happened, then what to
/// do about it. No apology, no error codes.
class AppException implements Exception {
  const AppException(this.message, {this.actionLabel = 'Try again'});

  final String message;
  final String actionLabel;

  /// The generic read failure the mock backend raises in its failure scenario.
  static const network = AppException(
    "The trail didn't load. Check your connection, then try again.",
  );

  static const notFound = AppException(
    "That's gone — it may have been deleted. Go back and pick another.",
    actionLabel: 'Go back',
  );

  @override
  String toString() => message;
}
