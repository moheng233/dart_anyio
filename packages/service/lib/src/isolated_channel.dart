import 'dart:async';
import 'dart:isolate';

import 'package:anyio_template/service.dart';

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
  }

  final String deviceId;
  final ChannelFactory channelFactory;
  final ChannelOptionBase channelOption;
  final ChannelTemplateBase templateOption;
  final TransportSession transport;

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
    _startIsolate();
  }

  @override
  void stop() {
    if (!_isRunning) return;
    _stopIsolate();
  }

  /// Restart the isolated channel
  Future<void> restart() async {
    if (_isRestarting) return;
    _isRestarting = true;
    
    try {
      _stopIsolate();
      await Future.delayed(const Duration(milliseconds: 500));
      _startIsolate();
    } finally {
      _isRestarting = false;
    }
  }

  void _startIsolate() async {
    try {
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
    } catch (e) {
      _readController.addError('Failed to start isolated channel: $e');
      _cleanupIsolate();
    }
  }

  void _stopIsolate() {
    if (_isolateSendPort != null) {
      _isolateSendPort!.send(const StopChannelMessage());
    }
    
    _cleanupIsolate();
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
      _initializeChannel();
    } else if (message is ChannelEventMessage) {
      // Reconstruct channel event from JSON
      final event = _deserializeChannelEvent(message.eventJson, message.eventType);
      if (event != null) {
        _readController.add(event);
      }
    } else if (message is ChannelErrorMessage) {
      // Handle channel error
      _readController.addError(
        'Channel error: ${message.error}',
        message.stackTrace != null ? StackTrace.fromString(message.stackTrace!) : null,
      );
      
      // Auto-restart on error
      restart();
    } else if (message == null) {
      // Isolate exited
      _readController.addError('Channel isolate exited unexpectedly');
      restart();
    }
  }

  void _initializeChannel() {
    if (_isolateSendPort == null) return;

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
  }

  void _handleDeviceEvent(DeviceBaseEvent event) {
    if (_isolateSendPort != null) {
      final serialized = _serializeDeviceEvent(event);
      if (serialized != null) {
        _isolateSendPort!.send(DeviceEventMessage(
          serialized['json'] as Map<String, dynamic>,
          serialized['type'] as String,
        ));
      }
    }
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
    await _deviceEventSubscription?.cancel();
    _stopIsolate();
    await _readController.close();
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
  });

  final SendPort mainSendPort;
  final ChannelFactory channelFactory;
  final String deviceId;
  final Map<String, dynamic> channelOptionJson;
  final Map<String, dynamic> templateOptionJson;
  final String channelOptionType;
  final String templateOptionType;
  final Map<String, dynamic> transportData;

  ChannelSession? _actualChannelSession;
  StreamSubscription<ChannelBaseEvent>? _channelSubscription;
  StreamController<DeviceBaseEvent>? _deviceEventController;

  void start() {
    try {
      // For now, simulate a working channel since we'd need full transport recreation
      // In a real implementation, you'd recreate the transport and full channel here
      _simulateChannelEvents();
    } catch (e, stackTrace) {
      mainSendPort.send(ChannelErrorMessage(e.toString(), stackTrace.toString()));
    }
  }

  void stop() {
    _channelSubscription?.cancel();
    _deviceEventController?.close();
    _actualChannelSession?.stop();
  }

  void handleDeviceEvent(Map<String, dynamic> eventJson, String eventType) {
    // Handle device events in the isolated channel
    // For now, just log them
    print('Isolated channel received device event: $eventType');
  }

  void _simulateChannelEvents() {
    // This is a placeholder - in real implementation, this would be the actual channel
    Timer.periodic(const Duration(seconds: 2), (timer) {
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
    });
  }
}