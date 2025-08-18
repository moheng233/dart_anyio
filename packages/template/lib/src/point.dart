import 'package:dart_mappable/dart_mappable.dart';
import 'package:meta/meta.dart';

part 'point.mapper.dart';

@MappableEnum()
enum PointType { bool, int, uint, float }

@immutable
@MappableClass()
class Point with PointMappable {
  const Point(this.deviceId, this.tagId, this.value);

  final String deviceId;
  final String tagId;
  final Object? value;
}

@immutable
@MappableClass()
class PointId with PointIdMappable {
  const PointId(this.deviceId, this.tagId);

  final String deviceId;
  final String tagId;
}
