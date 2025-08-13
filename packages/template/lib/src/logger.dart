abstract interface class Logger {
  void debug(dynamic msg, [Object? exception, StackTrace? stackTrace]);
  void info(dynamic msg, [Object? exception, StackTrace? stackTrace]);
  void error(dynamic msg, [Object? exception, StackTrace? stackTrace]);
}
