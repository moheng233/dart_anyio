import 'dart:isolate';

import 'package:dart_mappable/dart_mappable.dart';
import 'package:meta/meta.dart';

import '../point.dart';

part 'c2s.mapper.dart';

@immutable
@MappableClass()
sealed class ChannelBaseEvent with ChannelBaseEventMappable {
  const ChannelBaseEvent();
}

@MappableClass()
final class ChannelReadyEvent extends ChannelBaseEvent
    with ChannelReadyEventMappable {
  const ChannelReadyEvent(this.portForS2C);

  final SendPort portForS2C;
}

@MappableClass()
abstract interface class ChannelDeviceEvent extends ChannelBaseEvent
    with ChannelDeviceEventMappable {
  String get deviceId;
}

@MappableClass()
final class ChannelUpdateEvent extends ChannelBaseEvent
    with ChannelUpdateEventMappable
    implements ChannelDeviceEvent {
  const ChannelUpdateEvent(this.deviceId, this.updates);

  @override
  final String deviceId;
  final List<Variable> updates;
}

@MappableClass()
final class ChannelDeviceStatusEvent extends ChannelBaseEvent
    with ChannelDeviceStatusEventMappable
    implements ChannelDeviceEvent {
  const ChannelDeviceStatusEvent(
    this.deviceId,
    this.online, // ignore: avoid_positional_boolean_parameters 统一参数风格
  );

  @override
  final String deviceId;
  // true 表示设备正常，false 表示连接失败（具体失败原因通过其他途径上报）
  final bool online;
}

@MappableClass()
abstract class ChannelPerformanceEvent extends ChannelBaseEvent
    with ChannelPerformanceEventMappable {
  const ChannelPerformanceEvent(this.deviceId, this.eventName);

  final String? deviceId;

  final String eventName;
}

@MappableClass()
final class ChannelPerformanceTimeEvent extends ChannelPerformanceEvent
    with ChannelPerformanceTimeEventMappable {
  const ChannelPerformanceTimeEvent(
    super.deviceId,
    super.eventName, {
    required this.diffTime,
    this.startTime,
    this.endTime,
  });

  final DateTime? startTime;
  final DateTime? endTime;
  final Duration diffTime;
}

@MappableClass()
final class ChannelPerformanceCountEvent extends ChannelPerformanceEvent
    with ChannelPerformanceCountEventMappable {
  const ChannelPerformanceCountEvent(
    super.deviceId,
    super.eventName,
    this.count,
  );

  final int? count;
}

@MappableClass()
final class ChannelWritedEvent extends ChannelBaseEvent
    with ChannelWritedEventMappable
    implements ChannelDeviceEvent {
  const ChannelWritedEvent(
    this.deviceId,
    this.tagId,
    // ignore: avoid_positional_boolean_parameters 统一参数风格
    this.success, [
    this.message,
  ]);

  @override
  final String deviceId;
  final String tagId;
  final bool success;
  final String? message;
}
