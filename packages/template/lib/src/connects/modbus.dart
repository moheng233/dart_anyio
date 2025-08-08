import 'package:freezed_annotation/freezed_annotation.dart';

part 'modbus.freezed.dart';
part 'modbus.g.dart';

@JsonEnum(fieldRename: FieldRename.screamingSnake)
enum ModbusEncodeType {
  ab,
  ba,
  abcd,
  dcba,
}

enum ModbusPointType { bool, u16, u32, u64, i16, i32, i64, f16, f32, f64 }

@freezed
abstract class ModbusPoll with _$ModbusPoll {
  @Assert('[1, 2, 3, 4].contains(function)')
  const factory ModbusPoll({
    required int scanRate,
    required int function,
    required int address,
    required int length,
  }) = _ModbusPoll;

  factory ModbusPoll.fromJson(Map<String, dynamic> json) =>
      _$ModbusPollFromJson(json);
}

@freezed
abstract class ModbusReadPoint with _$ModbusReadPoint {
  @Assert('[1, 2, 3, 4].contains(function)')
  const factory ModbusReadPoint({
    required int function,
    required int address,
    required ModbusEncodeType encode,
    required ModbusPointType type,
  }) = _ModbusReadPoint;

  factory ModbusReadPoint.fromJson(Map<String, dynamic> json) =>
      _$ModbusReadPointFromJson(json);
}

@freezed
abstract class ModbusWritePoint with _$ModbusWritePoint {
  @Assert('[5, 6, 15, 16].contains(function)')
  const factory ModbusWritePoint({
    required int function,
    required int address,
    required ModbusEncodeType encode,
    required ModbusPointType type,
  }) = _ModbusWritePoint;

  factory ModbusWritePoint.fromJson(Map<String, dynamic> json) =>
      _$ModbusWritePointFromJson(json);
}
