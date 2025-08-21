import 'logger.dart';
import 'performance_monitor.dart';

/// Central logging and monitoring manager for the service
class LoggingManager {
  LoggingManager._();
  
  static LoggingManager? _instance;
  static LoggingManager get instance => _instance ??= LoggingManager._();

  Logger? _logger;
  PerformanceMonitor? _performanceMonitor;

  /// Initialize the logging system
  void initialize({
    Logger? logger,
    PerformanceMonitor? performanceMonitor,
  }) {
    _logger = logger ?? ConsoleLogger();
    _performanceMonitor = performanceMonitor ?? PerformanceMonitor();
  }

  /// Get the current logger
  Logger get logger {
    if (_logger == null) {
      throw StateError('LoggingManager not initialized. Call initialize() first.');
    }
    return _logger!;
  }

  /// Get the performance monitor
  PerformanceMonitor get performanceMonitor {
    if (_performanceMonitor == null) {
      throw StateError('LoggingManager not initialized. Call initialize() first.');
    }
    return _performanceMonitor!;
  }

  /// Configure device-specific log level
  void setDeviceLogLevel(String deviceId, LogLevel level) {
    logger.setDeviceLogLevel(deviceId, level);
  }

  /// Configure global log level
  void setGlobalLogLevel(LogLevel level) {
    logger.setGlobalLogLevel(level);
  }

  /// Get performance statistics for all devices
  Map<String, ChannelPerformanceStats> getPerformanceStats() {
    return performanceMonitor.getAllStats();
  }

  /// Get performance statistics for a specific device
  ChannelPerformanceStats? getDevicePerformanceStats(String deviceId) {
    return performanceMonitor.getStats(deviceId);
  }

  /// Clear performance metrics for a device
  void clearDevicePerformance(String deviceId) {
    performanceMonitor.clearDeviceMetrics(deviceId);
  }

  /// Log channel startup
  void logChannelStartup(String deviceId, {Map<String, dynamic>? context}) {
    logger.info('Channel starting up', deviceId: deviceId, context: context);
  }

  /// Log channel startup success
  void logChannelStartupSuccess(String deviceId, Duration duration) {
    logger.info(
      'Channel startup completed',
      deviceId: deviceId,
      context: {'duration_ms': duration.inMilliseconds},
    );
  }

  /// Log channel startup failure
  void logChannelStartupFailure(String deviceId, Object error, {StackTrace? stackTrace}) {
    logger.error(
      'Channel startup failed',
      deviceId: deviceId,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Log channel shutdown
  void logChannelShutdown(String deviceId, {Map<String, dynamic>? context}) {
    logger.info('Channel shutting down', deviceId: deviceId, context: context);
  }

  /// Log channel restart
  void logChannelRestart(String deviceId, int attempt, {Object? error}) {
    logger.warn(
      'Channel restart attempt $attempt',
      deviceId: deviceId,
      context: {'restart_attempt': attempt},
      error: error,
    );
  }

  /// Log channel error
  void logChannelError(String deviceId, Object error, {StackTrace? stackTrace, Map<String, dynamic>? context}) {
    logger.error(
      'Channel error occurred',
      deviceId: deviceId,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  /// Log channel communication error
  void logChannelCommunicationError(String deviceId, String operation, Object error) {
    logger.error(
      'Channel communication error during $operation',
      deviceId: deviceId,
      error: error,
      context: {'operation': operation},
    );
  }

  /// Log performance warning (slow operation)
  void logPerformanceWarning(String deviceId, PerformanceOperationType operation, Duration duration, Duration threshold) {
    logger.warn(
      'Slow $operation operation detected',
      deviceId: deviceId,
      context: {
        'operation': operation.toString(),
        'duration_ms': duration.inMilliseconds,
        'threshold_ms': threshold.inMilliseconds,
      },
    );
  }

  /// Log isolate crash
  void logIsolateCrash(String deviceId, {Object? error}) {
    logger.fatal(
      'Channel isolate crashed',
      deviceId: deviceId,
      error: error,
      context: {'isolate_crash': true},
    );
  }

  /// Log transport error
  void logTransportError(String deviceId, String transportType, Object error, {StackTrace? stackTrace}) {
    logger.error(
      'Transport error in $transportType',
      deviceId: deviceId,
      error: error,
      stackTrace: stackTrace,
      context: {'transport_type': transportType},
    );
  }

  /// Log device configuration
  void logDeviceConfiguration(String deviceId, Map<String, dynamic> config) {
    logger.debug(
      'Device configuration loaded',
      deviceId: deviceId,
      context: {'config': config},
    );
  }

  /// Shutdown the logging system
  Future<void> shutdown() async {
    if (_logger is FileLogger) {
      await (_logger as FileLogger).close();
    }
    
    _performanceMonitor?.clearAllMetrics();
  }
}

/// Convenience getters for global access
Logger get log => LoggingManager.instance.logger;
PerformanceMonitor get perfMon => LoggingManager.instance.performanceMonitor;