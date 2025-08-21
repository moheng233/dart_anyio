import 'dart:async';
import 'dart:collection';

import 'package:anyio_template/service.dart';

final class DeviceImpl extends Device {
  DeviceImpl({
    required this.deviceId,
    required this.template,
    required this.channelSession,
    required this.deviceEventController,
  });

  @override
  final String deviceId;
  
  final TemplateOption template;
  final ChannelSession channelSession;
  final StreamController<DeviceBaseEvent> deviceEventController;

  final _values = HashMap<String, Object?>();
  final _valueControllers = HashMap<String, StreamController<Object?>>();
  
  StreamSubscription<ChannelBaseEvent>? _channelSubscription;

  @override
  List<PointInfo> get points => template.points.values.toList();

  @override
  Map<String, Object?> get values => Map.unmodifiable(_values);

  /// Start listening to channel events
  void startListening() {
    _channelSubscription = channelSession.read.listen(_handleChannelEvent);
  }

  /// Stop listening to channel events
  void stopListening() {
    _channelSubscription?.cancel();
    _channelSubscription = null;
  }

  void _handleChannelEvent(ChannelBaseEvent event) {
    if (event is ChannelUpdateEvent && event.deviceId == deviceId) {
      for (final point in event.updates) {
        if (point.deviceId == deviceId) {
          _updateValue(point.tagId, point.value);
        }
      }
    }
  }

  void _updateValue(String tagId, Object? value) {
    _values[tagId] = value;
    
    // Notify listeners
    final controller = _valueControllers[tagId];
    if (controller != null && !controller.isClosed) {
      controller.add(value);
    }
  }

  @override
  Stream<Object?> listen(String tagId) {
    var controller = _valueControllers[tagId];
    if (controller == null) {
      controller = StreamController<Object?>.broadcast();
      _valueControllers[tagId] = controller;
    }
    return controller.stream;
  }

  @override
  Object? read(String tagId) {
    return _values[tagId];
  }

  @override
  void write(String tagId, Object? value) {
    final event = DeviceWriteEvent(deviceId, tagId, value);
    deviceEventController.add(event);
  }

  @override
  Future<bool> writeAsync(String tagId, Object? value) async {
    final completer = Completer<bool>();
    
    // Listen for write result
    late StreamSubscription subscription;
    subscription = channelSession.read.listen((event) {
      if (event is ChannelWriteResultEvent && 
          event.deviceId == deviceId) {
        subscription.cancel();
        completer.complete(event.success);
      }
    });

    // Send write event
    write(tagId, value);
    
    // Set timeout
    Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        subscription.cancel();
        completer.complete(false);
      }
    });

    return completer.future;
  }

  /// Dispose resources
  Future<void> dispose() async {
    stopListening();
    
    for (final controller in _valueControllers.values) {
      await controller.close();
    }
    _valueControllers.clear();
    _values.clear();
  }
}
