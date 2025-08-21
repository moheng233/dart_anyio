import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:anyio_template/service.dart';
import 'package:checked_yaml/checked_yaml.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

import 'channel_manager.dart';
import 'device.dart';
import 'isolated_channel.dart';
import 'transport_manager.dart';

/// Service gateway manager that orchestrates the entire system
final class ServiceManager {
  ServiceManager({
    required this.channelManager,
    required this.transportManager,
    this.enableChannelRestart = true,
    this.maxRestartAttempts = 3,
    this.restartDelaySeconds = 5,
  });

  final ChannelManager channelManager;
  final TransportManager transportManager;
  
  /// Whether to automatically restart failed channels
  final bool enableChannelRestart;
  
  /// Maximum number of restart attempts per channel
  final int maxRestartAttempts;
  
  /// Delay between restart attempts (seconds)
  final int restartDelaySeconds;

  final _devices = HashMap<String, DeviceImpl>();
  final _channelSessions = HashMap<String, ChannelSession>();
  final _deviceEventControllers = HashMap<String, StreamController<DeviceBaseEvent>>();
  final _channelErrorSubscriptions = HashMap<String, StreamSubscription>();
  final _restartAttempts = HashMap<String, int>();
  
  bool _isRunning = false;

  /// Load service configuration from file
  Future<ServiceOption> loadServiceConfig(File configFile) async {
    final content = await configFile.readAsString();
    return checkedYamlDecode(
      content,
      (json) => ServiceOption.fromJson(json!),
    );
  }

  /// Load device templates from directory
  Future<Map<String, TemplateOption>> loadTemplates(Directory templateDir) async {
    final templates = HashMap<String, TemplateOption>();
    
    await for (final entity in templateDir.list()) {
      if (entity is File && path.extension(entity.path) == '.yaml') {
        final templateName = path.basenameWithoutExtension(entity.path);
        final content = await entity.readAsString();
        final template = checkedYamlDecode(
          content,
          (json) => TemplateOption.fromJson(json!),
        );
        templates[templateName] = template;
      }
    }
    
    return templates;
  }

  /// Start the service with given configuration
  Future<void> start(ServiceOption config, Map<String, TemplateOption> templates) async {
    if (_isRunning) {
      throw StateError('Service is already running');
    }

    for (final deviceConfig in config.devices) {
      await _startDevice(deviceConfig, templates);
    }

    _isRunning = true;
  }

  /// Stop the service and cleanup resources
  Future<void> stop() async {
    if (!_isRunning) return;

    // Cancel all error subscriptions
    for (final subscription in _channelErrorSubscriptions.values) {
      await subscription.cancel();
    }
    _channelErrorSubscriptions.clear();

    // Stop all devices
    for (final device in _devices.values) {
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
  }

  /// Get device by ID
  DeviceImpl? getDevice(String deviceId) => _devices[deviceId];

  /// Get all devices
  Iterable<DeviceImpl> get devices => _devices.values;

  /// Get device IDs
  Iterable<String> get deviceIds => _devices.keys;

  /// Get channel session for device
  ChannelSession? getChannelSession(String deviceId) => _channelSessions[deviceId];

  /// Manually restart a channel
  Future<bool> restartChannel(String deviceId) async {
    if (!_isRunning) return false;

    if (channelManager is ChannelManagerImpl) {
      try {
        await (channelManager as ChannelManagerImpl).restartChannel(deviceId);
        _restartAttempts[deviceId] = 0; // Reset attempts on successful restart
        return true;
      } catch (e) {
        print('Failed to restart channel $deviceId: $e');
        return false;
      }
    }
    return false;
  }

  /// Get restart statistics
  Map<String, int> getRestartStats() => Map.unmodifiable(_restartAttempts);

  void _setupChannelErrorHandling(String deviceId, ChannelSession channelSession) {
    if (!enableChannelRestart) return;

    // Listen for channel errors for auto-restart
    final subscription = channelSession.read.handleError((error, stackTrace) {
      _handleChannelError(deviceId, error, stackTrace);
    }).listen(null);

    _channelErrorSubscriptions[deviceId] = subscription;
  }

  void _handleChannelError(String deviceId, dynamic error, StackTrace? stackTrace) async {
    print('Channel error for device $deviceId: $error');

    final attempts = _restartAttempts[deviceId] ?? 0;
    if (attempts >= maxRestartAttempts) {
      print('Max restart attempts reached for channel $deviceId');
      return;
    }

    _restartAttempts[deviceId] = attempts + 1;

    // Wait before attempting restart
    await Future.delayed(Duration(seconds: restartDelaySeconds));

    final success = await restartChannel(deviceId);
    if (success) {
      print('Successfully restarted channel $deviceId (attempt ${attempts + 1})');
    } else {
      print('Failed to restart channel $deviceId (attempt ${attempts + 1})');
    }
  }

  Future<void> _startDevice(DeviceOption deviceConfig, Map<String, TemplateOption> templates) async {
    final template = templates[deviceConfig.template];
    if (template == null) {
      throw StateError('Template not found: ${deviceConfig.template}');
    }

    // Create transport session
    final transport = transportManager.create(deviceConfig.transportOption);
    await transport.open();

    // Create device event controller
    final deviceEventController = StreamController<DeviceBaseEvent>.broadcast();
    _deviceEventControllers[deviceConfig.name] = deviceEventController;

    // Create channel session
    final channelSession = channelManager.create(
      deviceConfig.name,
      deviceEvent: deviceEventController.stream,
      transport: transport,
      channelOption: deviceConfig.channel,
      templateOption: template.template,
    );

    _channelSessions[deviceConfig.name] = channelSession;

    // Create device implementation
    final device = DeviceImpl(
      deviceId: deviceConfig.name,
      template: template,
      channelSession: channelSession,
      deviceEventController: deviceEventController,
    );

    _devices[deviceConfig.name] = device;

    // Start channel session
    channelSession.open();
    
    // Setup error handling for channel restarts
    _setupChannelErrorHandling(deviceConfig.name, channelSession);
    
    // Start listening to channel events
    device.startListening();
  }
}