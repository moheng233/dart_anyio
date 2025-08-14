import 'dart:typed_data';

import 'package:anyio_template/service.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'template.freezed.dart';
part 'template.g.dart';

@JsonEnum(fieldRename: FieldRename.screamingSnake)
enum ModbusEndianType {
  /// ABCD: 大端序，字节顺序 [A,B,C,D] - 标准大端
  abcd(Endian.big, swap: false),

  /// DCBA: 小端序，字节顺序 [D,C,B,A] - 标准小端
  dcba(Endian.little, swap: false),

  /// BADC: 大端字节序但字交换，字节顺序 [B,A,D,C] - 字内大端，字间交换
  badc(Endian.big, swap: true),

  /// CDAB: 小端字节序但字交换，字节顺序 [C,D,A,B] - 字内小端，字间交换
  cdab(Endian.little, swap: true);

  const ModbusEndianType(this.endian, {required this.swap});

  final Endian endian;
  final bool swap;
}

@freezed
abstract class ChannelOptionForModbus with _$ChannelOptionForModbus {
  const factory ChannelOptionForModbus({
    required bool isRtu,
    required int unitId,
  }) = _ChannelOptionForModbus;

  factory ChannelOptionForModbus.fromJson(Map<dynamic, dynamic> json) =>
      _$ChannelOptionForModbusFromJson(json);
}

@freezed
abstract class ChannelTemplateForModbus with _$ChannelTemplateForModbus {
  const factory ChannelTemplateForModbus({
    required List<ModbusPoll> polls,
    required List<ModbusWritePoint> writes,
  }) = _ChannelTemplateForModbus;

  factory ChannelTemplateForModbus.fromJson(Map<dynamic, dynamic> json) =>
      _$ChannelTemplateForModbusFromJson(json);
}

@freezed
abstract class ModbusPoll with _$ModbusPoll {
  const factory ModbusPoll({
    required int intervalTime,
    required int function,
    required int begin,
    required int length,
    required List<ModbusReadPoint> points,
  }) = _ModbusPoll;

  factory ModbusPoll.fromJson(Map<dynamic, dynamic> json) =>
      _$ModbusPollFromJson(json);
}

@freezed
abstract class ModbusReadPoint with _$ModbusReadPoint {
  const factory ModbusReadPoint({
    required String tag,
    required int offset,
    @Default(1) double scale,
    @Default(1) int length,
    @Default(ModbusEndianType.dcba) ModbusEndianType endian,
    @Default(PointType.uint) PointType type,
  }) = _ModbusReadPoint;

  factory ModbusReadPoint.fromJson(Map<dynamic, dynamic> json) =>
      _$ModbusReadPointFromJson(json);
}

@freezed
abstract class ModbusWritePoint with _$ModbusWritePoint {
  const factory ModbusWritePoint({
    required String tag,
    required int function,
    required int address,
    required ModbusEndianType encode,
    required PointType type,
  }) = _ModbusWritePoint;

  factory ModbusWritePoint.fromJson(Map<dynamic, dynamic> json) =>
      _$ModbusWritePointFromJson(json);
}
