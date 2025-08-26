import 'package:dart_mappable/dart_mappable.dart';
import 'package:meta/meta.dart';

import '../point.dart';
import '../template.dart';

part 's2c.mapper.dart';

@immutable
@MappableClass()
sealed class DeviceBaseEvent with DeviceBaseEventMappable {
  const DeviceBaseEvent();
}

@MappableClass()
final class DeviceActionInvokeEvent extends DeviceBaseEvent
    with DeviceActionInvokeEventMappable {
  const DeviceActionInvokeEvent(this.deviceId, this.actionId, this.value);

  final String deviceId;
  final String actionId;
  final Object? value;
}
