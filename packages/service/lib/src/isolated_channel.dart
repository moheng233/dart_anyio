import 'dart:async';
import 'dart:isolate';

import 'package:anyio_template/service.dart';

import 'logging/logging.dart';

/// Message types for inter-isolate communication
abstract class IsolateMessage {
  const IsolateMessage();
}

/// Initialize channel in isolate
class InitChannelMessage extends IsolateMessage {
  const InitChannelMessage({
    required this.deviceId,
    required this.channelOptionJson,
    required this.templateOptionJson,
    required this.channelOptionType,
    required this.templateOptionType,
    required this.transportData,
  });

  final String deviceId;
  final Map<String, dynamic> channelOptionJson;
  final Map<String, dynamic> templateOptionJson;
  final String channelOptionType;
  final String templateOptionType;
  final Map<String, dynamic> transportData; // Serialized transport data
}

/// Start channel operations
class StartChannelMessage extends IsolateMessage {
  const StartChannelMessage();
}

/// Stop channel operations
class StopChannelMessage extends IsolateMessage {
  const StopChannelMessage();
}

/// Device event forwarded to channel
class DeviceEventMessage extends IsolateMessage {
  const DeviceEventMessage(this.eventJson, this.eventType);
  final Map<String, dynamic> eventJson;
  final String eventType;
}

/// Channel event from isolated channel
class ChannelEventMessage extends IsolateMessage {
  const ChannelEventMessage(this.eventJson, this.eventType);
  final Map<String, dynamic> eventJson;
  final String eventType;
}

/// Performance metric from isolated channel
class PerformanceMetricMessage extends IsolateMessage {
  const PerformanceMetricMessage({
    required this.deviceId,
    required this.operationType,
    required this.durationMicroseconds,
    required this.timestampMillis,
    required this.success,
    this.details,
    this.pollUnitIndex,
    this.pollCycleId,
  });

  final String deviceId;
  final String operationType; // PerformanceOperationType as string
  final int durationMicroseconds;
  final int timestampMillis;
  final bool success;
  final Map<String, dynamic>? details;
  final int? pollUnitIndex;
  final String? pollCycleId;
}

/// Error message from isolated channel
class ChannelErrorMessage extends IsolateMessage {
  const ChannelErrorMessage(this.error, this.stackTrace);
  final String error;
  final String? stackTrace;
}

/// Isolate ready signal
class IsolateReadyMessage extends IsolateMessage {
  const IsolateReadyMessage();
}

/// Wrapper for running a channel session in an isolated environment
class IsolatedChannelSession extends ChannelSessionBase<ChannelOptionBase, ChannelTemplateBase> {
  IsolatedChannelSession({
    required this.deviceId,
    required this.channelFactory,
    required this.channelOption,
    required this.templateOption,
    required this.transport,
    required Stream<DeviceBaseEvent> deviceEvent,
  }) : super(write: deviceEvent) {
    _deviceEventSubscription = write.listen(_handleDeviceEvent);
    _logger = LoggingManager.instance.logger;
    _performanceMonitor = LoggingManager.instance.performanceMonitor;
  }

  final String deviceId;
  final ChannelFactory channelFactory;
  final ChannelOptionBase channelOption;
  final ChannelTemplateBase templateOption;
  final TransportSession transport;

  late final Logger _logger;
  late final PerformanceMonitor _performanceMonitor;

  Isolate? _isolate;
  SendPort? _isolateSendPort;
  ReceivePort? _isolateReceivePort;
  StreamSubscription<DeviceBaseEvent>? _deviceEventSubscription;
  
  final _readController = StreamController<ChannelBaseEvent>.broadcast();
  bool _isRunning = false;
  bool _isRestarting = false;

  @override
  Stream<ChannelBaseEvent> get read => _readController.stream;

  @override
  void open() {
    if (_isRunning) return;
    
    _logger.info('Opening isolated channel', deviceId: deviceId);
    _startIsolate();
  }

  @override
  void stop() {
    if (!_isRunning) return;
    
    _logger.info('Stopping isolated channel', deviceId: deviceId);
    _stopIsolate();
  }

  /// Restart the isolated channel
  Future<void> restart() async {
    if (_isRestarting) return;
    _isRestarting = true;
    
    final restartTimer = _performanceMonitor.startRestartTimer(deviceId);
    
    try {
      _logger.warn('Restarting isolated channel', deviceId: deviceId);
      _stopIsolate();
      await Future.delayed(const Duration(milliseconds: 500));
      _startIsolate();
      
      restartTimer.complete();
      _logger.info('Isolated channel restart completed', deviceId: deviceId);
    } catch (e, stackTrace) {
      restartTimer.fail();
      _logger.error('Isolated channel restart failed', 
                   deviceId: deviceId, 
                   error: e, 
                   stackTrace: stackTrace);
      rethrow;
    } finally {
      _isRestarting = false;
    }
  }

  void _startIsolate() async {
    final startupTimer = _performanceMonitor.startStartupTimer(deviceId);
    
    try {
      _logger.debug('Creating isolate for channel', deviceId: deviceId);
      
      // Create receive port for communication
      _isolateReceivePort = ReceivePort();
      
      // Listen to messages from isolate
      _isolateReceivePort!.listen(_handleIsolateMessage);

      // Create isolate startup data
      final startupData = IsolateStartupData(
        mainSendPort: _isolateReceivePort!.sendPort,
        channelFactory: channelFactory,
      );

      // Spawn isolate
      _isolate = await Isolate.spawn(
        _isolateEntryPoint,
        startupData,
        onError: _isolateReceivePort!.sendPort,
        onExit: _isolateReceivePort!.sendPort,
      );

      _isRunning = true;
      startupTimer.complete();
      _logger.info('Isolate created successfully', deviceId: deviceId);
    } catch (e, stackTrace) {
      startupTimer.fail();
      _logger.error('Failed to start isolated channel', 
                   deviceId: deviceId, 
                   error: e, 
                   stackTrace: stackTrace);
      _readController.addError('Failed to start isolated channel: $e');
      _cleanupIsolate();
    }
  }

  void _stopIsolate() {
    final shutdownTimer = _performanceMonitor.startShutdownTimer(deviceId);
    
    try {
      _logger.debug('Stopping isolate', deviceId: deviceId);
      
      if (_isolateSendPort != null) {
        _isolateSendPort!.send(const StopChannelMessage());
      }
      
      _cleanupIsolate();
      shutdownTimer.complete();
      _logger.debug('Isolate stopped', deviceId: deviceId);
    } catch (e) {
      shutdownTimer.fail();
      _logger.warn('Error during isolate shutdown', deviceId: deviceId, error: e);
    }
  }

  void _cleanupIsolate() {
    _isolate?.kill();
    _isolate = null;
    _isolateSendPort = null;
    _isolateReceivePort?.close();
    _isolateReceivePort = null;
    _isRunning = false;
  }

  void _handleIsolateMessage(dynamic message) {
    if (message is SendPort) {
      // Isolate is ready, save send port and initialize
      _isolateSendPort = message;
      _logger.debug('Isolate ready, initializing channel', deviceId: deviceId);
      _initializeChannel();
    } else if (message is ChannelEventMessage) {
      // Reconstruct channel event from JSON
      final event = _deserializeChannelEvent(message.eventJson, message.eventType);
      if (event != null) {
        _readController.add(event);
      }
    } else if (message is PerformanceMetricMessage) {
      // Forward performance metric to monitor
      _handlePerformanceMetric(message);
    } else if (message is ChannelErrorMessage) {
      // Handle channel error
      _logger.error('Channel error in isolate', 
                   deviceId: deviceId, 
                   error: message.error,
                   context: {'isolate_error': true});
      
      _readController.addError(
        'Channel error: ${message.error}',
        message.stackTrace != null ? StackTrace.fromString(message.stackTrace!) : null,
      );
      
      // Auto-restart on error
      restart();
    } else if (message == null) {
      // Isolate exited
      _logger.fatal('Channel isolate exited unexpectedly', 
                   deviceId: deviceId,
                   context: {'isolate_crash': true});
      _readController.addError('Channel isolate exited unexpectedly');
      restart();
    }
  }

  void _initializeChannel() {
    if (_isolateSendPort == null) return;

    _logger.debug('Sending initialization message', deviceId: deviceId);

    // Send initialization message
    final initMessage = InitChannelMessage(
      deviceId: deviceId,
      channelOptionJson: _serializeChannelOption(channelOption),
      templateOptionJson: _serializeTemplateOption(templateOption),
      channelOptionType: channelOption.runtimeType.toString(),
      templateOptionType: templateOption.runtimeType.toString(),
      transportData: _serializeTransport(transport),
    );
    
    _isolateSendPort!.send(initMessage);
    
    // Start channel
    _isolateSendPort!.send(const StartChannelMessage());
    _logger.info('Channel initialization sent', deviceId: deviceId);
  }

  void _handleDeviceEvent(DeviceBaseEvent event) {
    if (_isolateSendPort != null) {
      final serialized = _serializeDeviceEvent(event);
      if (serialized != null) {
        _logger.trace('Forwarding device event to isolate', 
                     deviceId: deviceId,
                     context: {'event_type': serialized['type']});
        
        _isolateSendPort!.send(DeviceEventMessage(
          serialized['json'] as Map<String, dynamic>,
          serialized['type'] as String,
        ));
      }
    }
  }

  void _handlePerformanceMetric(PerformanceMetricMessage message) {
    // Convert back to PerformanceOperationType
    PerformanceOperationType? operationType;
    for (final type in PerformanceOperationType.values) {
      if (type.toString() == message.operationType) {
        operationType = type;
        break;
      }
    }
    
    if (operationType == null) return;
    
    // Reconstruct PerformanceMetric
    final metric = PerformanceMetric(
      deviceId: message.deviceId,
      operationType: operationType,
      duration: Duration(microseconds: message.durationMicroseconds),
      timestamp: DateTime.fromMillisecondsSinceEpoch(message.timestampMillis),
      success: message.success,
      details: message.details,
      pollUnitIndex: message.pollUnitIndex,
      pollCycleId: message.pollCycleId,
    );
    
    _performanceMonitor.recordMetric(metric);
  }

  Map<String, dynamic> _serializeChannelOption(ChannelOptionBase option) {
    // Use the factory's mapper to serialize
    try {
      final mapper = channelFactory.channelOptionMapper;
      return mapper.toMap(option);
    } catch (e) {
      return {}; // Fallback to empty map
    }
  }

  Map<String, dynamic> _serializeTemplateOption(ChannelTemplateBase option) {
    // Use the factory's mapper to serialize
    try {
      final mapper = channelFactory.templateOptionMapper;
      return mapper.toMap(option);
    } catch (e) {
      return {}; // Fallback to empty map
    }
  }

  Map<String, dynamic> _serializeTransport(TransportSession transport) {
    // For now, serialize basic transport data
    // In a real implementation, you'd need proper transport serialization
    return {
      'type': transport.runtimeType.toString(),
      // Add serializable transport data here
    };
  }

  Map<String, dynamic>? _serializeDeviceEvent(DeviceBaseEvent event) {
    // Simple serialization for device events
    if (event is DeviceWriteEvent) {
      return {
        'json': {
          'deviceId': event.deviceId,
          'tagId': event.tagId,
          'value': event.value,
        },
        'type': 'DeviceWriteEvent',
      };
    }
    return null;
  }

  ChannelBaseEvent? _deserializeChannelEvent(Map<String, dynamic> json, String type) {
    // Simple deserialization for channel events
    switch (type) {
      case 'ChannelUpdateEvent':
        final deviceId = json['deviceId'] as String;
        final updatesJson = json['updates'] as List<dynamic>;
        final updates = updatesJson.map((u) => Point(
          u['deviceId'] as String,
          u['tagId'] as String,
          u['value'],
        )).toList();
        return ChannelUpdateEvent(deviceId, updates);
      case 'ChannelWriteResultEvent':
        return ChannelWriteResultEvent(
          json['deviceId'] as String,
          json['success'] as bool,
        );
      default:
        return null;
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    _logger.debug('Disposing isolated channel', deviceId: deviceId);
    
    await _deviceEventSubscription?.cancel();
    _stopIsolate();
    await _readController.close();
    
    _logger.debug('Isolated channel disposed', deviceId: deviceId);
  }

  /// Entry point for the isolated channel
  static void _isolateEntryPoint(IsolateStartupData startupData) {
    final receivePort = ReceivePort();
    
    // Send back our send port
    startupData.mainSendPort.send(receivePort.sendPort);
    
    IsolatedChannelWorker? worker;
    
    receivePort.listen((message) {
      try {
        if (message is InitChannelMessage) {
          worker = IsolatedChannelWorker(
            mainSendPort: startupData.mainSendPort,
            channelFactory: startupData.channelFactory,
            deviceId: message.deviceId,
            channelOptionJson: message.channelOptionJson,
            templateOptionJson: message.templateOptionJson,
            channelOptionType: message.channelOptionType,
            templateOptionType: message.templateOptionType,
            transportData: message.transportData,
          );
        } else if (message is StartChannelMessage) {
          worker?.start();
        } else if (message is StopChannelMessage) {
          worker?.stop();
          Isolate.exit();
        } else if (message is DeviceEventMessage) {
          worker?.handleDeviceEvent(message.eventJson, message.eventType);
        }
      } catch (e, stackTrace) {
        startupData.mainSendPort.send(ChannelErrorMessage(e.toString(), stackTrace.toString()));
      }
    });
  }
}

/// Data needed to start an isolate
class IsolateStartupData {
  const IsolateStartupData({
    required this.mainSendPort,
    required this.channelFactory,
  });

  final SendPort mainSendPort;
  final ChannelFactory channelFactory;
}

/// Worker that runs inside the isolated channel
class IsolatedChannelWorker {
  IsolatedChannelWorker({
    required this.mainSendPort,
    required this.channelFactory,
    required this.deviceId,
    required this.channelOptionJson,
    required this.templateOptionJson,
    required this.channelOptionType,
    required this.templateOptionType,
    required this.transportData,
  }) {
    // Initialize simple console logging for isolate
    _logger = ConsoleLogger(globalLevel: LogLevel.info);
    _performanceMonitor = PerformanceMonitor();
  }

  final SendPort mainSendPort;
  final ChannelFactory channelFactory;
  final String deviceId;
  final Map<String, dynamic> channelOptionJson;
  final Map<String, dynamic> templateOptionJson;
  final String channelOptionType;
  final String templateOptionType;
  final Map<String, dynamic> transportData;

  late final Logger _logger;
  late final PerformanceMonitor _performanceMonitor;

  ChannelSession? _actualChannelSession;
  StreamSubscription<ChannelBaseEvent>? _channelSubscription;
  StreamController<DeviceBaseEvent>? _deviceEventController;
  Timer? _pollTimer;

  void start() {
    final startupTimer = _performanceMonitor.startStartupTimer(deviceId);
    
    try {
      _logger.info('Starting isolated channel worker', deviceId: deviceId);
      
      // For now, simulate a working channel since we'd need full transport recreation
      // In a real implementation, you'd recreate the transport and full channel here
      _simulateChannelEvents();
      
      startupTimer.complete();
      _logger.info('Isolated channel worker started successfully', deviceId: deviceId);
    } catch (e, stackTrace) {
      startupTimer.fail();
      _logger.error('Failed to start isolated channel worker', 
                   deviceId: deviceId, 
                   error: e, 
                   stackTrace: stackTrace);
      mainSendPort.send(ChannelErrorMessage(e.toString(), stackTrace.toString()));
    }
  }

  void stop() {
    final shutdownTimer = _performanceMonitor.startShutdownTimer(deviceId);
    
    try {
      _logger.info('Stopping isolated channel worker', deviceId: deviceId);
      
      _pollTimer?.cancel();
      _channelSubscription?.cancel();
      _deviceEventController?.close();
      _actualChannelSession?.stop();
      
      shutdownTimer.complete();
      _logger.info('Isolated channel worker stopped', deviceId: deviceId);
    } catch (e) {
      shutdownTimer.fail();
      _logger.warn('Error during worker shutdown', deviceId: deviceId, error: e);
    }
  }

  void handleDeviceEvent(Map<String, dynamic> eventJson, String eventType) {
    final writeTimer = _performanceMonitor.startWriteTimer(deviceId, 
        details: {'event_type': eventType});
    
    try {
      _logger.debug('Handling device event', 
                   deviceId: deviceId,
                   context: {'event_type': eventType});
      
      // Handle device events in the isolated channel
      // For now, just log them
      // In a real implementation, this would forward to the actual channel
      
      writeTimer.complete();
    } catch (e) {
      writeTimer.fail();
      _logger.error('Error handling device event', 
                   deviceId: deviceId, 
                   error: e,
                   context: {'event_type': eventType});
    }
  }

  void _simulateChannelEvents() {
    // This is a placeholder - in real implementation, this would be the actual channel
    var pollCycleCounter = 0;
    
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      final pollCycleId = 'cycle_${pollCycleCounter++}';
      final pollTimer = _performanceMonitor.startPollTimer(deviceId, pollCycleId: pollCycleId);
      
      try {
        _logger.trace('Starting poll cycle', 
                     deviceId: deviceId,
                     context: {'poll_cycle_id': pollCycleId});
        
        // Simulate poll units within the cycle
        _simulatePollUnits(pollCycleId);
        
        // Send simulated channel update event
        final eventJson = {
          'deviceId': deviceId,
          'updates': [
            {
              'deviceId': deviceId,
              'tagId': 'status',
              'value': DateTime.now().millisecondsSinceEpoch % 100,
            }
          ],
        };
        
        mainSendPort.send(ChannelEventMessage(eventJson, 'ChannelUpdateEvent'));
        
        pollTimer.complete();
        _logger.trace('Poll cycle completed', 
                     deviceId: deviceId,
                     context: {'poll_cycle_id': pollCycleId});
        
        // Send performance metrics to main isolate
        _sendPerformanceMetrics();
        
      } catch (e) {
        pollTimer.fail();
        _logger.error('Poll cycle failed', 
                     deviceId: deviceId, 
                     error: e,
                     context: {'poll_cycle_id': pollCycleId});
      }
    });
  }

  void _simulatePollUnits(String pollCycleId) {
    // Simulate multiple poll units within a cycle
    for (int i = 0; i < 3; i++) {
      final pollUnitTimer = _performanceMonitor.startPollUnitTimer(
        deviceId, 
        i, 
        pollCycleId: pollCycleId
      );
      
      try {
        // Simulate some work with busy waiting to measure actual time
        final startTime = DateTime.now();
        final targetDuration = Duration(milliseconds: 10 + (i * 5));
        
        // Simple busy wait simulation
        while (DateTime.now().difference(startTime) < targetDuration) {
          // Simulate processing work
        }
        
        pollUnitTimer.complete();
        _logger.trace('Poll unit completed', 
                     deviceId: deviceId,
                     context: {
                       'poll_cycle_id': pollCycleId,
                       'poll_unit_index': i,
                       'target_duration_ms': targetDuration.inMilliseconds,
                     });
      } catch (e) {
        pollUnitTimer.fail();
        _logger.warn('Poll unit failed', 
                    deviceId: deviceId, 
                    error: e,
                    context: {
                      'poll_cycle_id': pollCycleId,
                      'poll_unit_index': i,
                    });
      }
    }
  }

  void _sendPerformanceMetrics() {
    // Send recent performance metrics to main isolate
    final recentMetrics = _performanceMonitor.getRecentMetrics(deviceId, limit: 10);
    
    for (final metric in recentMetrics) {
      final message = PerformanceMetricMessage(
        deviceId: metric.deviceId,
        operationType: metric.operationType.toString(),
        durationMicroseconds: metric.duration.inMicroseconds,
        timestampMillis: metric.timestamp.millisecondsSinceEpoch,
        success: metric.success,
        details: metric.details,
        pollUnitIndex: metric.pollUnitIndex,
        pollCycleId: metric.pollCycleId,
      );
      
      mainSendPort.send(message);
    }
    
    // Clear sent metrics to avoid duplicate sending
    _performanceMonitor.clearDeviceMetrics(deviceId);
  }
}