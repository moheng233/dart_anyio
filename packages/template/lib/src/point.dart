import 'package:freezed_annotation/freezed_annotation.dart';

import '../service.dart';

typedef Point = (PointId, PointValue);

@immutable
final class PointId {
  const PointId(this.deviceId, this.tagId);

  final String deviceId;
  final String tagId;

  @override
  int get hashCode => Object.hash(deviceId, tagId);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PointId &&
            deviceId == other.deviceId &&
            tagId == other.tagId);
  }
}
