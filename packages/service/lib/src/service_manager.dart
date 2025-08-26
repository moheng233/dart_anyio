import 'dart:async';
import 'dart:io';

import 'package:anyio_template/service.dart';
import 'package:checked_yaml/checked_yaml.dart';
import 'package:path/path.dart' as path;

import 'channel_manager.dart';
import 'logging/logging.dart';

/// Service gateway manager that orchestrates the entire system
final class ServiceManager {
  ServiceManager({
    required this.channelManager,
    Logger? logger,
    PerformanceMonitor? performanceMonitor,
    this.performanceThresholds = const {},
  }) {
    // Initialize logging system
    LoggingManager.instance.initialize(
      logger: logger,
      performanceMonitor: performanceMonitor,
    );

    _logger = LoggingManager.instance.logger;
    _performanceMonitor = LoggingManager.instance.performanceMonitor;
  }

  final ChannelManagerImpl channelManager;

  /// Performance thresholds for warnings (operation type -> threshold duration)
  final Map<PerformanceOperationType, Duration> performanceThresholds;

  late final Logger _logger;
  late final PerformanceMonitor _performanceMonitor;

  bool _isRunning = false;

  /// Clear performance metrics for a device
  void clearDevicePerformanceMetrics(String deviceId) {
    _performanceMonitor.clearDeviceMetrics(deviceId);
    _logger.debug('Performance metrics cleared', deviceId: deviceId);
  }

  /// Get performance statistics for a specific device
  ChannelPerformanceStats? getDevicePerformanceStats(String deviceId) {
    return _performanceMonitor.getStats(deviceId);
  }

  /// Get performance statistics for all devices
  Map<String, ChannelPerformanceStats> getPerformanceStats() {
    return _performanceMonitor.getAllStats();
  }

  // 统一读写接口代理
  Object? readValue(String deviceId, String tagId) =>
      channelManager.readValue(deviceId, tagId);

  Stream<Object?> listenValue(String deviceId, String tagId) =>
      channelManager.listenValue(deviceId, tagId);

  void invokeAction(String deviceId, String actionId, Object? value) =>
      channelManager.invokeAction(deviceId, actionId, value);

  /// Set log level for a specific device
  void setDeviceLogLevel(String deviceId, LogLevel level) {
    _logger
      ..setDeviceLogLevel(deviceId, level)
      ..info(
        'Log level changed',
        deviceId: deviceId,
        context: {'level': level.name},
      );
  }

  /// Set global log level
  void setGlobalLogLevel(LogLevel level) {
    _logger
      ..setGlobalLogLevel(level)
      ..info('Global log level changed', context: {'level': level.name});
  }

  /// Start the service with given configuration
  Future<void> start(
    ServiceOption config,
    Map<String, TemplateOption> templates,
  ) async {
    if (_isRunning) {
      throw StateError('Service is already running');
    }

    _logger.info('Starting service with ${config.devices.length} devices');
    // 通道管理器应由外部构造并 initialize 完成；此处不再重复初始化。
    _isRunning = true;
    _logger.info('Service started successfully');
  }

  /// Stop the service and cleanup resources
  Future<void> stop() async {
    if (!_isRunning) return;

    _logger.info('Stopping service');

    // 通道管理停止交由上层实现；此处仅标记状态并关闭日志。

    _isRunning = false;

    _logger.info('Service stopped');

    // Shutdown logging system
    await LoggingManager.instance.shutdown();
  }

  // 已移除逐设备启动逻辑；由 initialize 统一处理。

  /// Load service configuration from file
  static Future<ServiceOption> loadServiceConfig(File configFile) async {
    final content = await configFile.readAsString();
    return checkedYamlDecode(
      content,
      (json) => ServiceOptionMapper.fromMap(json!.cast<String, dynamic>()),
    );
  }

  /// Load device templates from directory
  static Future<Map<String, TemplateOption>> loadTemplates(
    Directory templateDir,
  ) async {
    final templates = <String, TemplateOption>{};

    await for (final entity in templateDir.list()) {
      if (entity is File && path.extension(entity.path) == '.yaml') {
        final templateName = path.basenameWithoutExtension(entity.path);
        final content = await entity.readAsString();
        final template = checkedYamlDecode(
          content,
          (json) => TemplateOptionMapper.fromMap(json!.cast<String, dynamic>()),
        );
        templates[templateName] = template;
      }
    }

    return templates;
  }
}
