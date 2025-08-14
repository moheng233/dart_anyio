import 'package:freezed_annotation/freezed_annotation.dart';

import 'point.dart';
import 'template.dart';

part 'event.freezed.dart';

@immutable
sealed class ChannelBaseEvent {
  const ChannelBaseEvent();

  String get deviceId;
}

@immutable
@freezed
final class ChannelUpdateEvent extends ChannelBaseEvent
    with _$ChannelUpdateEvent {
  const ChannelUpdateEvent(this.deviceId, this.updates);

  @override
  final String deviceId;
  @override
  final List<Point> updates;
}

@immutable
@freezed
final class ChannelWriteResultEvent extends ChannelBaseEvent
    with _$ChannelWriteResultEvent {
  const ChannelWriteResultEvent(this.deviceId, {required this.success});

  @override
  final String deviceId;
  @override
  final bool success;
}

@immutable
sealed class DeviceBaseEvent {
  const DeviceBaseEvent();
}

@immutable
@freezed
final class DeviceWriteEvent extends DeviceBaseEvent with _$DeviceWriteEvent {
  const DeviceWriteEvent(this.deviceId, this.tagId, this.value);

  @override
  final String deviceId;
  @override
  final String tagId;
  @override
  final PointValue value;
}
