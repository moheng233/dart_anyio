import 'dart:async';
import 'dart:isolate';

import 'package:anyio_template/service.dart';
import 'package:dart_mappable/dart_mappable.dart';

import 'logging/logging.dart';

part 'isolated_channel.mapper.dart';

/// Message types for inter-isolate communication
@MappableClass()
sealed class IsolateMessage with IsolateMessageMappable {
  const IsolateMessage();
}

/// Initialize channel in isolate
@MappableClass()
class InitChannelMessage extends IsolateMessage
    with InitChannelMessageMappable {
  const InitChannelMessage({
    required this.deviceId,
    required this.channelOptionJson,
    required this.templateOptionJson,
    required this.channelOptionType,
    required this.templateOptionType,
    required this.transportData,
  });

  final String deviceId;
  final Map<dynamic, dynamic> channelOptionJson;
  final Map<dynamic, dynamic> templateOptionJson;
  final String channelOptionType;
  final String templateOptionType;
  final Map<String, dynamic> transportData; // Serialized transport data
}

/// Start channel operations
@MappableClass()
class StartChannelMessage extends IsolateMessage
    with StartChannelMessageMappable {
  const StartChannelMessage();
}

/// Stop channel operations
@MappableClass()
class StopChannelMessage extends IsolateMessage
    with StopChannelMessageMappable {
  const StopChannelMessage();
}

/// Device event forwarded to channel
@MappableClass()
class DeviceEventMessage extends IsolateMessage
    with DeviceEventMessageMappable {
  const DeviceEventMessage(this.event);
  final DeviceBaseEvent event;
}

/// Channel event from isolated channel
@MappableClass()
class ChannelEventMessage extends IsolateMessage
    with ChannelEventMessageMappable {
  const ChannelEventMessage(this.event);
  final ChannelBaseEvent event;
}

/// Performance metric from isolated channel
@MappableClass()
class PerformanceMetricMessage extends IsolateMessage
    with PerformanceMetricMessageMappable {
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
@MappableClass()
class ChannelErrorMessage extends IsolateMessage
    with ChannelErrorMessageMappable {
  const ChannelErrorMessage(this.error, this.stackTrace);
  final String error;
  final String? stackTrace;
}

/// Isolate ready signal
@MappableClass()
class IsolateReadyMessage extends IsolateMessage
    with IsolateReadyMessageMappable {
  const IsolateReadyMessage();
}

/// Wrapper for running a channel session in an isolated environment
final class IsolatedChannelSession
    extends ChannelSessionBase<ChannelOptionBase, ChannelTemplateBase> {
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
      await Future<void>.delayed(const Duration(milliseconds: 500));
      unawaited(_startIsolate());

      restartTimer.complete();
      _logger.info('Isolated channel restart completed', deviceId: deviceId);
    } on Exception catch (e, stackTrace) {
      restartTimer.fail();
      _logger.error(
        'Isolated channel restart failed',
        deviceId: deviceId,
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      _isRestarting = false;
    }
  }

  Future<void> _startIsolate() async {
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
    } on Exception catch (e, stackTrace) {
      startupTimer.fail();
      _logger.error(
        'Failed to start isolated channel',
        deviceId: deviceId,
        error: e,
        stackTrace: stackTrace,
      );
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
    } on Exception catch (e) {
      shutdownTimer.fail();
      _logger.warn(
        'Error during isolate shutdown',
        deviceId: deviceId,
        error: e,
      );
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
      _readController.add(message.event);
    } else if (message is PerformanceMetricMessage) {
      // Forward performance metric to monitor
      _handlePerformanceMetric(message);
    } else if (message is ChannelErrorMessage) {
      // Handle channel error
      _logger.error(
        'Channel error in isolate',
        deviceId: deviceId,
        error: message.error,
        context: {'isolate_error': true},
      );

      _readController.addError(
        'Channel error: ${message.error}',
        message.stackTrace != null
            ? StackTrace.fromString(message.stackTrace!)
            : null,
      );

      // Auto-restart on error
      restart();
    } else if (message == null) {
      // Isolate exited
      _logger.fatal(
        'Channel isolate exited unexpectedly',
        deviceId: deviceId,
        context: {'isolate_crash': true},
      );
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
      final serialized = event.toMap();
      _logger.trace(
        'Forwarding device event to isolate',
        deviceId: deviceId,
        context: {'event_type': serialized['type']},
      );

      _isolateSendPort!.send(event.toMap());
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

  Map<dynamic, dynamic> _serializeChannelOption(ChannelOptionBase option) {
    // Use the factory's mapper to serialize
    try {
      final mapper = channelFactory.channelOptionMapper;
      return mapper.encodeMap(option);
    } on Exception {
      return {}; // Fallback to empty map
    }
  }

  Map<dynamic, dynamic> _serializeTemplateOption(ChannelTemplateBase option) {
    // Use the factory's mapper to serialize
    try {
      final mapper = channelFactory.templateOptionMapper;
      return mapper.encodeMap(option);
    } on Exception {
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
          worker?.handleDeviceEvent(message.event);
        }
      } on Exception catch (e, stackTrace) {
        startupData.mainSendPort.send(
          ChannelErrorMessage(e.toString(), stackTrace.toString()),
        );
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
    _logger = ConsoleLogger();
    _performanceMonitor = PerformanceMonitor();
  }

  final SendPort mainSendPort;
  final ChannelFactory channelFactory;
  final String deviceId;
  final Map<dynamic, dynamic> channelOptionJson;
  final Map<dynamic, dynamic> templateOptionJson;
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

      // TODO(me): Recreate the real channel and transport here.

      startupTimer.complete();
      _logger.info(
        'Isolated channel worker started successfully',
        deviceId: deviceId,
      );
    } on Exception catch (e, stackTrace) {
      startupTimer.fail();
      _logger.error(
        'Failed to start isolated channel worker',
        deviceId: deviceId,
        error: e,
        stackTrace: stackTrace,
      );
      mainSendPort.send(
        ChannelErrorMessage(e.toString(), stackTrace.toString()),
      );
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
    } on Exception catch (e) {
      shutdownTimer.fail();
      _logger.warn(
        'Error during worker shutdown',
        deviceId: deviceId,
        error: e,
      );
    }
  }

  void handleDeviceEvent(DeviceBaseEvent event) {
    final writeTimer = _performanceMonitor.startWriteTimer(
      deviceId,
      details: {'event_type': event.runtimeType},
    );

    try {
      _logger.debug(
        'Handling device event',
        deviceId: deviceId,
        context: {'event_type': event.runtimeType},
      );

      // Handle device events in the isolated channel
      // For now, just log them
      // In a real implementation, this would forward to the actual channel

      writeTimer.complete();
    } on Exception catch (e) {
      writeTimer.fail();
      _logger.error(
        'Error handling device event',
        deviceId: deviceId,
        error: e,
        context: {'event_type': event.runtimeType},
      );
    }
  }
}
