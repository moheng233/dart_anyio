@MappableLib(caseStyle: CaseStyle.snakeCase)
library;

import 'dart:typed_data';

import 'package:dart_mappable/dart_mappable.dart';
import 'package:meta/meta.dart';

part 'point.mapper.dart';

@MappableEnum()
enum PointType { bool, int, uint, float }

@MappableEnum(caseStyle: CaseStyle.lowerCase)
enum EndianType {
  /// ABCD: 大端序，字节顺序 [A,B,C,D] - 标准大端
  abcd(Endian.big, swap: false),

  /// DCBA: 小端序，字节顺序 [D,C,B,A] - 标准小端
  dcba(Endian.little, swap: false),

  /// BADC: 大端字节序但字交换，字节顺序 [B,A,D,C] - 字内大端，字间交换
  badc(Endian.big, swap: true),

  /// CDAB: 小端字节序但字交换，字节顺序 [C,D,A,B] - 字内小端，字间交换
  cdab(Endian.little, swap: true);

  const EndianType(this.endian, {required this.swap});

  final Endian endian;
  final bool swap;
}

@MappableEnum(caseStyle: CaseStyle.lowerCase)
enum AccessType {
  r(),
  rw(write: true),
  w(read: false, write: true);

  const AccessType({this.read = true, this.write = false});

  final bool read;
  final bool write;
}

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

@MappableClass(discriminatorKey: 'type')
sealed class PointInfo with PointInfoMappable {
  const PointInfo({
    this.access = AccessType.r,
    this.displayName,
    this.detailed,
  });

  final AccessType access;
  final String? displayName;
  final String? detailed;
}

@MappableClass(discriminatorValue: 'value')
final class PointInfoForValue extends PointInfo with PointInfoForValueMappable {
  const PointInfoForValue({
    this.read,
    this.write,
    super.access,
    super.displayName,
    super.detailed,
  });

  final String? read;
  final String? write;
}

@MappableClass(discriminatorValue: 'enum')
final class PointInfoForEnum extends PointInfo with PointInfoForEnumMappable {
  PointInfoForEnum({
    required this.values,
    super.access,
    super.displayName,
    super.detailed,
  });

  final Map<String, num> values;
}
