import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:anyio_template/service.dart';
import 'package:checked_yaml/checked_yaml.dart';
import 'package:path/path.dart' as path;

import 'channel_manager.dart';
import 'device.dart';
import 'logging/logging.dart';

/// Service gateway manager that orchestrates the entire system
final class ServiceManager {
  ServiceManager({
    required this.channelManager,
    required this.transportManager,
    this.enableChannelRestart = true,
    this.maxRestartAttempts = 3,
    this.restartDelaySeconds = 5,
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

  final ChannelManager channelManager;
  final TransportManager transportManager;

  /// Whether to automatically restart failed channels
  final bool enableChannelRestart;

  /// Maximum number of restart attempts per channel
  final int maxRestartAttempts;

  /// Delay between restart attempts (seconds)
  final int restartDelaySeconds;

  /// Performance thresholds for warnings (operation type -> threshold duration)
  final Map<PerformanceOperationType, Duration> performanceThresholds;

  late final Logger _logger;
  late final PerformanceMonitor _performanceMonitor;

  final _devices = HashMap<String, DeviceImpl>();
  final _channelSessions = HashMap<String, ChannelSession>();
  final _deviceEventControllers =
      HashMap<String, StreamController<DeviceBaseEvent>>();
  final _restartAttempts = HashMap<String, int>();

  bool _isRunning = false;

  /// Load service configuration from file
  Future<ServiceOption> loadServiceConfig(File configFile) async {
    final content = await configFile.readAsString();
    return checkedYamlDecode(
      content,
      (json) => ServiceOptionMapper.fromMap(json!.cast<String, dynamic>()),
    );
  }

  /// Load device templates from directory
  Future<Map<String, TemplateOption>> loadTemplates(
    Directory templateDir,
  ) async {
    final templates = HashMap<String, TemplateOption>();

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

  /// Start the service with given configuration
  Future<void> start(
    ServiceOption config,
    Map<String, TemplateOption> templates,
  ) async {
    if (_isRunning) {
      throw StateError('Service is already running');
    }

    _logger.info('Starting service with ${config.devices.length} devices');

    for (final deviceConfig in config.devices) {
      await _startDevice(deviceConfig, templates);
    }

    _isRunning = true;
    _logger.info('Service started successfully');
  }

  /// Stop the service and cleanup resources
  Future<void> stop() async {
    if (!_isRunning) return;

    _logger.info('Stopping service');

    // Stop all devices
    for (final device in _devices.values) {
      _logger.debug('Stopping device', deviceId: device.deviceId);
      await device.dispose();
    }

    // Stop channel manager (handles both regular and isolated channels)
    if (channelManager is ChannelManagerImpl) {
      await (channelManager as ChannelManagerImpl).stopAll();
    } else {
      // Fallback for regular channel sessions
      for (final session in _channelSessions.values) {
        session.stop();
      }
    }

    // Close all device event controllers
    for (final controller in _deviceEventControllers.values) {
      await controller.close();
    }

    _channelSessions.clear();
    _deviceEventControllers.clear();
    _devices.clear();
    _restartAttempts.clear();
    _isRunning = false;

    _logger.info('Service stopped');

    // Shutdown logging system
    await LoggingManager.instance.shutdown();
  }

  /// Get device by ID
  DeviceImpl? getDevice(String deviceId) => _devices[deviceId];

  /// Get all devices
  Iterable<DeviceImpl> get devices => _devices.values;

  /// Get device IDs
  Iterable<String> get deviceIds => _devices.keys;

  /// Get channel session for device
  ChannelSession? getChannelSession(String deviceId) =>
      _channelSessions[deviceId];

  /// Manually restart a channel
  Future<bool> restartChannel(String deviceId) async {
    if (!_isRunning) return false;

    final restartTimer = _performanceMonitor.startRestartTimer(deviceId);

    if (channelManager is ChannelManagerImpl) {
      try {
        _logger.info('Manually restarting channel', deviceId: deviceId);
        await (channelManager as ChannelManagerImpl).restartChannel(deviceId);
        _restartAttempts[deviceId] = 0; // Reset attempts on successful restart

        restartTimer.complete();
        _logger.info('Channel restart successful', deviceId: deviceId);
        return true;
      } on Exception catch (e, stackTrace) {
        restartTimer.fail();
        _logger.error(
          'Failed to restart channel',
          deviceId: deviceId,
          error: e,
          stackTrace: stackTrace,
        );
        return false;
      }
    }

    restartTimer.fail();
    return false;
  }

  /// Get restart statistics
  Map<String, int> getRestartStats() => Map.unmodifiable(_restartAttempts);

  /// Get performance statistics for all devices
  Map<String, ChannelPerformanceStats> getPerformanceStats() {
    return _performanceMonitor.getAllStats();
  }

  /// Get performance statistics for a specific device
  ChannelPerformanceStats? getDevicePerformanceStats(String deviceId) {
    return _performanceMonitor.getStats(deviceId);
  }

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

  /// Clear performance metrics for a device
  void clearDevicePerformanceMetrics(String deviceId) {
    _performanceMonitor.clearDeviceMetrics(deviceId);
    _logger.debug('Performance metrics cleared', deviceId: deviceId);
  }

  void _setupChannelErrorHandling(
    String deviceId,
    ChannelSession channelSession,
  ) {
    if (!enableChannelRestart) return;

    // Listen for channel errors for auto-restart
    // ignore: cancel_subscriptions
    channelSession.read.handleError((Object error, StackTrace? stackTrace) {
      _handleChannelError(deviceId, error, stackTrace);
    });
  }

  Future<void> _handleChannelError(
    String deviceId,
    dynamic error,
    StackTrace? stackTrace,
  ) async {
    _logger.error(
      'Channel error detected',
      deviceId: deviceId,
      error: error,
      stackTrace: stackTrace,
    );

    final attempts = _restartAttempts[deviceId] ?? 0;
    if (attempts >= maxRestartAttempts) {
      _logger.fatal(
        'Max restart attempts reached',
        deviceId: deviceId,
        context: {'attempts': attempts, 'max_attempts': maxRestartAttempts},
      );
      return;
    }

    _restartAttempts[deviceId] = attempts + 1;

    _logger.warn(
      'Attempting channel restart',
      deviceId: deviceId,
      context: {'attempt': attempts + 1, 'max_attempts': maxRestartAttempts},
    );

    // Wait before attempting restart
    await Future.delayed(Duration(seconds: restartDelaySeconds));

    final success = await restartChannel(deviceId);
    if (success) {
      _logger.info(
        'Auto-restart successful',
        deviceId: deviceId,
        context: {'attempt': attempts + 1},
      );
    } else {
      _logger.error(
        'Auto-restart failed',
        deviceId: deviceId,
        context: {'attempt': attempts + 1},
      );
    }
  }

  Future<void> _startDevice(
    DeviceOption deviceConfig,
    Map<String, TemplateOption> templates,
  ) async {
    final deviceId = deviceConfig.name;
    final startupTimer = _performanceMonitor.startStartupTimer(deviceId);

    try {
      _logger.info(
        'Starting device',
        deviceId: deviceId,
        context: {
          'template': deviceConfig.template,
          'transport': deviceConfig.transportOption.runtimeType.toString(),
        },
      );

      final template = templates[deviceConfig.template];
      if (template == null) {
        throw StateError('Template not found: ${deviceConfig.template}');
      }

      // Log device configuration
      _logger.debug(
        'Device configuration loaded',
        deviceId: deviceId,
        context: {
          'template': deviceConfig.template,
          'channel_type': deviceConfig.channel.runtimeType.toString(),
        },
      );

      // Create transport session
      final transport = transportManager.create(deviceConfig.transportOption);
      await transport.open();

      // Create device event controller
      final deviceEventController =
          StreamController<DeviceBaseEvent>.broadcast();
      _deviceEventControllers[deviceId] = deviceEventController;

      // Create channel session
      final channelSession = channelManager.create(
        deviceId,
        deviceEvent: deviceEventController.stream,
        transport: transport,
        channelOption: deviceConfig.channel,
        templateOption: template.template,
      );

      _channelSessions[deviceId] = channelSession;

      // Create device implementation
      final device = DeviceImpl(
        deviceId: deviceId,
        template: template,
        channelSession: channelSession,
        deviceEventController: deviceEventController,
      );

      _devices[deviceId] = device;

      // Start channel session
      channelSession.open();

      // Setup error handling for channel restarts
      _setupChannelErrorHandling(deviceId, channelSession);

      // Start listening to channel events
      device.startListening();

      startupTimer.complete();
      _logger.info('Device started successfully', deviceId: deviceId);
    } catch (e, stackTrace) {
      startupTimer.fail();
      _logger.error(
        'Failed to start device',
        deviceId: deviceId,
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}
