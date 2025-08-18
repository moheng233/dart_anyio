import 'package:dart_mappable/dart_mappable.dart';
import 'package:meta/meta.dart';

import 'point.dart';
import 'template.dart';

part 'event.mapper.dart';

@immutable
sealed class ChannelBaseEvent {
  const ChannelBaseEvent();

  String get deviceId;
}

@immutable
@MappableClass()
final class ChannelUpdateEvent extends ChannelBaseEvent
    with ChannelUpdateEventMappable {
  const ChannelUpdateEvent(this.deviceId, this.updates);

  @override
  final String deviceId;
  final List<Point> updates;
}

@immutable
@MappableClass()
final class ChannelWriteResultEvent extends ChannelBaseEvent
    with ChannelWriteResultEventMappable {
  const ChannelWriteResultEvent(this.deviceId, {required this.success});

  @override
  final String deviceId;
  final bool success;
}

@immutable
sealed class DeviceBaseEvent {
  const DeviceBaseEvent();
}

@immutable
@MappableClass()
final class DeviceWriteEvent extends DeviceBaseEvent
    with DeviceWriteEventMappable {
  const DeviceWriteEvent(this.deviceId, this.tagId, this.value);

  final String deviceId;
  final String tagId;
  final Object? value;
}
