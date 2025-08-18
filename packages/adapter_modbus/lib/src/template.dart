import 'dart:typed_data';

import 'package:anyio_template/service.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'template.mapper.dart';

@MappableEnum(caseStyle: CaseStyle.lowerCase)
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

@MappableEnum(caseStyle: CaseStyle.lowerCase)
enum ModbusAccessType {
  r(),
  rw(write: true),
  w(read: false, write: true);

  const ModbusAccessType({this.read = true, this.write = false});

  final bool read;
  final bool write;
}

@MappableClass(discriminatorKey: 'adapter', discriminatorValue: 'modbus')
final class ChannelOptionForModbus extends ChannelOptionBase
    with ChannelOptionForModbusMappable {
  const ChannelOptionForModbus({
    required this.isRtu,
    required this.unitId,
  });

  final bool isRtu;
  final int unitId;
}

@MappableClass(discriminatorKey: 'adapter', discriminatorValue: 'modbus')
final class ChannelTemplateForModbus extends ChannelTemplateBase
    with ChannelTemplateForModbusMappable {
  const ChannelTemplateForModbus(
    super.name,
    super.version, {
    required this.polls,
  });

  final List<ModbusPoll> polls;
}

@MappableClass()
final class ModbusPoll with ModbusPollMappable {
  const ModbusPoll({
    required this.intervalTime,
    required this.function,
    required this.begin,
    required this.length,
    required this.points,
  });

  final int intervalTime;
  final int function;
  final int begin;
  final int length;
  final List<ModbusPoint> points;
}

@MappableClass()
final class ModbusPoint with ModbusPointMappable {
  const ModbusPoint({
    required this.tag,
    required this.offset,
    this.scale = 1,
    this.length = 1,
    this.endian = ModbusEndianType.dcba,
    this.type = PointType.uint,
    this.access = ModbusAccessType.r,
  });

  final String tag;
  final int offset;
  final double scale;
  final int length;
  final ModbusEndianType endian;
  final PointType type;
  final ModbusAccessType access;
}
