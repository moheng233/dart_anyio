import 'package:freezed_annotation/freezed_annotation.dart';

import 'template.dart';

part 'point.freezed.dart';

enum PointType { bool, int, uint, float }

@immutable
@freezed
final class Point with _$Point {
  const Point(this.deviceId, this.tagId, this.value);

  @override
  final String deviceId;

  @override
  final String tagId;

  @override
  final PointValue value;
}

@immutable
@freezed
final class PointId with _$PointId {
  const PointId(this.deviceId, this.tagId);

  @override
  final String deviceId;
  
  @override
  final String tagId;
}
