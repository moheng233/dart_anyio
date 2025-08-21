import 'dart:io';

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

/// Structured log entry
class LogEntry {
  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    required this.deviceId,
    this.context,
    this.error,
    this.stackTrace,
  });

  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? deviceId;
  final Map<String, dynamic>? context;
  final Object? error;
  final StackTrace? stackTrace;

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('${timestamp.toIso8601String()} ');
    buffer.write('[${level.name}] ');
    
    if (deviceId != null) {
      buffer.write('[$deviceId] ');
    }
    
    buffer.write(message);
    
    if (context != null && context!.isNotEmpty) {
      buffer.write(' | Context: $context');
    }
    
    if (error != null) {
      buffer.write(' | Error: $error');
    }
    
    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }
    
    return buffer.toString();
  }
}

/// Logger interface for channel and device logging
abstract class Logger {
  void trace(String message, {String? deviceId, Map<String, dynamic>? context});
  void debug(String message, {String? deviceId, Map<String, dynamic>? context});
  void info(String message, {String? deviceId, Map<String, dynamic>? context});
  void warn(String message, {String? deviceId, Map<String, dynamic>? context, Object? error});
  void error(String message, {String? deviceId, Map<String, dynamic>? context, Object? error, StackTrace? stackTrace});
  void fatal(String message, {String? deviceId, Map<String, dynamic>? context, Object? error, StackTrace? stackTrace});
  
  /// Set log level for a specific device
  void setDeviceLogLevel(String deviceId, LogLevel level);
  
  /// Set global default log level
  void setGlobalLogLevel(LogLevel level);
  
  /// Get effective log level for a device
  LogLevel getEffectiveLogLevel(String? deviceId);
}

/// Console logger implementation with device-specific log levels
class ConsoleLogger implements Logger {
  ConsoleLogger({LogLevel globalLevel = LogLevel.info}) : _globalLevel = globalLevel;

  LogLevel _globalLevel;
  final Map<String, LogLevel> _deviceLogLevels = <String, LogLevel>{};

  @override
  void setDeviceLogLevel(String deviceId, LogLevel level) {
    _deviceLogLevels[deviceId] = level;
  }

  @override
  void setGlobalLogLevel(LogLevel level) {
    _globalLevel = level;
  }

  @override
  LogLevel getEffectiveLogLevel(String? deviceId) {
    if (deviceId != null && _deviceLogLevels.containsKey(deviceId)) {
      return _deviceLogLevels[deviceId]!;
    }
    return _globalLevel;
  }

  @override
  void trace(String message, {String? deviceId, Map<String, dynamic>? context}) {
    _log(LogLevel.trace, message, deviceId: deviceId, context: context);
  }

  @override
  void debug(String message, {String? deviceId, Map<String, dynamic>? context}) {
    _log(LogLevel.debug, message, deviceId: deviceId, context: context);
  }

  @override
  void info(String message, {String? deviceId, Map<String, dynamic>? context}) {
    _log(LogLevel.info, message, deviceId: deviceId, context: context);
  }

  @override
  void warn(String message, {String? deviceId, Map<String, dynamic>? context, Object? error}) {
    _log(LogLevel.warn, message, deviceId: deviceId, context: context, error: error);
  }

  @override
  void error(String message, {String? deviceId, Map<String, dynamic>? context, Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.error, message, deviceId: deviceId, context: context, error: error, stackTrace: stackTrace);
  }

  @override
  void fatal(String message, {String? deviceId, Map<String, dynamic>? context, Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.fatal, message, deviceId: deviceId, context: context, error: error, stackTrace: stackTrace);
  }

  void _log(LogLevel level, String message, {
    String? deviceId,
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final effectiveLevel = getEffectiveLogLevel(deviceId);
    if (!effectiveLevel.isEnabledFor(level)) {
      return;
    }

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      deviceId: deviceId,
      context: context,
      error: error,
      stackTrace: stackTrace,
    );

    // Write to stderr for errors/warnings, stdout for others
    if (level.level >= LogLevel.warn.level) {
      stderr.writeln(entry.toString());
    } else {
      stdout.writeln(entry.toString());
    }
  }
}

/// File logger implementation with rotation support
class FileLogger implements Logger {
  FileLogger({
    required this.logFilePath,
    LogLevel globalLevel = LogLevel.info,
    this.maxFileSizeBytes = 10 * 1024 * 1024, // 10MB
    this.maxBackupFiles = 5,
  }) : _globalLevel = globalLevel;

  final String logFilePath;
  final int maxFileSizeBytes;
  final int maxBackupFiles;
  
  LogLevel _globalLevel;
  final Map<String, LogLevel> _deviceLogLevels = <String, LogLevel>{};
  IOSink? _logSink;

  Future<void> _ensureLogFile() async {
    if (_logSink != null) return;

    final logFile = File(logFilePath);
    await logFile.parent.create(recursive: true);
    
    // Check if rotation is needed
    if (await logFile.exists()) {
      final stat = await logFile.stat();
      if (stat.size > maxFileSizeBytes) {
        await _rotateLogFile();
      }
    }

    _logSink = logFile.openWrite(mode: FileMode.append);
  }

  Future<void> _rotateLogFile() async {
    final logFile = File(logFilePath);
    
    // Rotate existing backup files
    for (int i = maxBackupFiles - 1; i >= 1; i--) {
      final oldFile = File('$logFilePath.$i');
      if (await oldFile.exists()) {
        final newFile = File('$logFilePath.${i + 1}');
        await oldFile.rename(newFile.path);
      }
    }
    
    // Move current log to backup
    if (await logFile.exists()) {
      final backupFile = File('$logFilePath.1');
      await logFile.rename(backupFile.path);
    }
  }

  @override
  void setDeviceLogLevel(String deviceId, LogLevel level) {
    _deviceLogLevels[deviceId] = level;
  }

  @override
  void setGlobalLogLevel(LogLevel level) {
    _globalLevel = level;
  }

  @override
  LogLevel getEffectiveLogLevel(String? deviceId) {
    if (deviceId != null && _deviceLogLevels.containsKey(deviceId)) {
      return _deviceLogLevels[deviceId]!;
    }
    return _globalLevel;
  }

  @override
  void trace(String message, {String? deviceId, Map<String, dynamic>? context}) {
    _log(LogLevel.trace, message, deviceId: deviceId, context: context);
  }

  @override
  void debug(String message, {String? deviceId, Map<String, dynamic>? context}) {
    _log(LogLevel.debug, message, deviceId: deviceId, context: context);
  }

  @override
  void info(String message, {String? deviceId, Map<String, dynamic>? context}) {
    _log(LogLevel.info, message, deviceId: deviceId, context: context);
  }

  @override
  void warn(String message, {String? deviceId, Map<String, dynamic>? context, Object? error}) {
    _log(LogLevel.warn, message, deviceId: deviceId, context: context, error: error);
  }

  @override
  void error(String message, {String? deviceId, Map<String, dynamic>? context, Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.error, message, deviceId: deviceId, context: context, error: error, stackTrace: stackTrace);
  }

  @override
  void fatal(String message, {String? deviceId, Map<String, dynamic>? context, Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.fatal, message, deviceId: deviceId, context: context, error: error, stackTrace: stackTrace);
  }

  void _log(LogLevel level, String message, {
    String? deviceId,
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    final effectiveLevel = getEffectiveLogLevel(deviceId);
    if (!effectiveLevel.isEnabledFor(level)) {
      return;
    }

    await _ensureLogFile();

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      deviceId: deviceId,
      context: context,
      error: error,
      stackTrace: stackTrace,
    );

    _logSink?.writeln(entry.toString());
    await _logSink?.flush();
  }

  Future<void> close() async {
    await _logSink?.close();
    _logSink = null;
  }
}

/// Multi-logger that forwards to multiple logger implementations
class MultiLogger implements Logger {
  MultiLogger(this.loggers);

  final List<Logger> loggers;

  @override
  void setDeviceLogLevel(String deviceId, LogLevel level) {
    for (final logger in loggers) {
      logger.setDeviceLogLevel(deviceId, level);
    }
  }

  @override
  void setGlobalLogLevel(LogLevel level) {
    for (final logger in loggers) {
      logger.setGlobalLogLevel(level);
    }
  }

  @override
  LogLevel getEffectiveLogLevel(String? deviceId) {
    // Use the first logger's level as the effective level
    return loggers.isNotEmpty ? loggers.first.getEffectiveLogLevel(deviceId) : LogLevel.info;
  }

  @override
  void trace(String message, {String? deviceId, Map<String, dynamic>? context}) {
    for (final logger in loggers) {
      logger.trace(message, deviceId: deviceId, context: context);
    }
  }

  @override
  void debug(String message, {String? deviceId, Map<String, dynamic>? context}) {
    for (final logger in loggers) {
      logger.debug(message, deviceId: deviceId, context: context);
    }
  }

  @override
  void info(String message, {String? deviceId, Map<String, dynamic>? context}) {
    for (final logger in loggers) {
      logger.info(message, deviceId: deviceId, context: context);
    }
  }

  @override
  void warn(String message, {String? deviceId, Map<String, dynamic>? context, Object? error}) {
    for (final logger in loggers) {
      logger.warn(message, deviceId: deviceId, context: context, error: error);
    }
  }

  @override
  void error(String message, {String? deviceId, Map<String, dynamic>? context, Object? error, StackTrace? stackTrace}) {
    for (final logger in loggers) {
      logger.error(message, deviceId: deviceId, context: context, error: error, stackTrace: stackTrace);
    }
  }

  @override
  void fatal(String message, {String? deviceId, Map<String, dynamic>? context, Object? error, StackTrace? stackTrace}) {
    for (final logger in loggers) {
      logger.fatal(message, deviceId: deviceId, context: context, error: error, stackTrace: stackTrace);
    }
  }
}