import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:anyio_template/service.dart';
import 'package:checked_yaml/checked_yaml.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

import 'channel_manager.dart';
import 'device.dart';
import 'transport_manager.dart';

/// Service gateway manager that orchestrates the entire system
final class ServiceManager {
  ServiceManager({
    required this.channelManager,
    required this.transportManager,
  });

  final ChannelManager channelManager;
  final TransportManager transportManager;

  final _devices = HashMap<String, DeviceImpl>();
  final _channelSessions = HashMap<String, ChannelSession>();
  final _deviceEventControllers = HashMap<String, StreamController<DeviceBaseEvent>>();
  
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

    // Stop all channel sessions
    for (final session in _channelSessions.values) {
      session.stop();
    }

    // Close all device event controllers
    for (final controller in _deviceEventControllers.values) {
      await controller.close();
    }

    _channelSessions.clear();
    _deviceEventControllers.clear();
    _devices.clear();
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
    
    // Start listening to channel events
    device.startListening();
  }
}