/// Log levels for filtering log messages
enum LogLevel {
  trace(0, 'TRACE'),
  debug(1, 'DEBUG'),
  info(2, 'INFO '),
  warn(3, 'WARN '),
  error(4, 'ERROR'),
  fatal(5, 'FATAL');

  const LogLevel(this.level, this.name);

  final int level;
  final String name;

  bool isEnabledFor(LogLevel other) => level <= other.level;
}

abstract class Logger {
  void trace(String message, {String? deviceId, Map<String, dynamic>? context});
  void debug(String message, {String? deviceId, Map<String, dynamic>? context});
  void info(String message, {String? deviceId, Map<String, dynamic>? context});
  void warn(
    String message, {
    String? deviceId,
    Map<String, dynamic>? context,
    Object? error,
  });
  void error(
    String message, {
    String? deviceId,
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  });
  void fatal(
    String message, {
    String? deviceId,
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  });

  /// Set log level for a specific device
  void setDeviceLogLevel(String deviceId, LogLevel level);

  /// Set global default log level
  void setGlobalLogLevel(LogLevel level);

  /// Get effective log level for a device
  LogLevel getEffectiveLogLevel(String? deviceId);
}
