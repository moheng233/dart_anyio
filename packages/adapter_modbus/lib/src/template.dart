import 'dart:convert';
import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'template.freezed.dart';
part 'template.g.dart';

@JsonEnum(fieldRename: FieldRename.screamingSnake)
enum ModbusEndianType {
  ab(Endian.big),
  ba(Endian.little);

  const ModbusEndianType(this.endian);

  final Endian endian;
}

enum ModbusPointType { bool, int, uint, float }

@freezed
abstract class ModbusDeviceExt with _$ModbusDeviceExt {
  const factory ModbusDeviceExt({
    required bool isRtu,
    required int unitId,
  }) = _ModbusDeviceExt;

  factory ModbusDeviceExt.fromJson(Map<dynamic, dynamic> json) =>
      _$ModbusDeviceExtFromJson(json);
}

@freezed
abstract class ModbusTemplate with _$ModbusTemplate {
  const factory ModbusTemplate({
    required List<ModbusPoll> polls,
    required List<ModbusReadPoint> reads,
    required List<ModbusWritePoint> writes,
  }) = _ModbusTemplate;

  factory ModbusTemplate.fromJson(Map<dynamic, dynamic> json) =>
      _$ModbusTemplateFromJson(json);
}

@freezed
abstract class ModbusPoll with _$ModbusPoll {
  @Assert('[1, 2, 3, 4].contains(function)')
  const factory ModbusPoll({
    required int intervalTime,
    required int function,
    required int address,
    required int length,
  }) = _ModbusPoll;

  factory ModbusPoll.fromJson(Map<dynamic, dynamic> json) =>
      _$ModbusPollFromJson(json);
}

@freezed
abstract class ModbusReadPoint with _$ModbusReadPoint {
  @Assert('[1, 2, 3, 4].contains(function)')
  const factory ModbusReadPoint({
    required String tag,
    required int function,
    required int address,
    @Default(1) int length,
    @Default(ModbusEndianType.ab) ModbusEndianType endian,
    @Default(ModbusPointType.uint) ModbusPointType type,
  }) = _ModbusReadPoint;

  factory ModbusReadPoint.fromJson(Map<dynamic, dynamic> json) =>
      _$ModbusReadPointFromJson(json);
}

@freezed
abstract class ModbusWritePoint with _$ModbusWritePoint {
  @Assert('[5, 6, 15, 16].contains(function)')
  const factory ModbusWritePoint({
    required String tag,
    required int function,
    required int address,
    required ModbusEndianType encode,
    required ModbusPointType type,
  }) = _ModbusWritePoint;

  factory ModbusWritePoint.fromJson(Map<dynamic, dynamic> json) =>
      _$ModbusWritePointFromJson(json);
}
