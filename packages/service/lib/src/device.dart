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
  // Single pending write per tagId. New writes will fail previous pending ones.
  final _pendingWriteByTag = HashMap<String, _PendingWrite>();

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
    // Handle write results first to resolve pending write futures
    if (event is ChannelWriteResultEvent && event.deviceId == deviceId) {
      final pending = _pendingWriteByTag.remove(event.tagId);
      if (pending != null) {
        pending.timer.cancel();
        if (!pending.completer.isCompleted) {
          pending.completer.complete(event.success);
        }
      }
      return;
    }

    if (event is ChannelUpdateEvent && event.deviceId == deviceId) {
      for (final point in event.updates) {
        if (point.deviceId == deviceId) {
          _updateValue(point.tagId, point.value);
        }
      }
    }
  }

  void _updateValue(String tagId, Object? newValue) {
    final oldValue = _values[tagId];

    if (oldValue != newValue) {
      _values[tagId] = newValue;

      final controller = _valueControllers[tagId];
      if (controller != null && !controller.isClosed) {
        controller.add(newValue);
      }
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

    // Cancel existing pending write for this tag (new write overrides it)
    final existed = _pendingWriteByTag.remove(tagId);
    if (existed != null) {
      existed.timer.cancel();
      if (!existed.completer.isCompleted) {
        existed.completer.complete(false);
      }
    }

    // Register new pending write; result is completed in _handleChannelEvent
    // Create timeout timer first, then store record
    final timeoutTimer = Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        // Only clear if this completer is still the current one for the tag
        final current = _pendingWriteByTag[tagId];
        if (current != null && identical(current.completer, completer)) {
          _pendingWriteByTag.remove(tagId);
        }
        completer.complete(false);
      }
    });

    final pending = (completer: completer, tagId: tagId, timer: timeoutTimer);
    _pendingWriteByTag[tagId] = pending;

    // Send write event
    write(tagId, value);

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

typedef _PendingWrite = ({
  Completer<bool> completer,
  String tagId,
  Timer timer,
});
