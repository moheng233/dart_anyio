@MappableLib(caseStyle: CaseStyle.snakeCase)
library;

import 'dart:typed_data';

import 'package:anyio_template/service.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'template.mapper.dart';

@MappableClass(discriminatorValue: 'modbus')
final class ChannelOptionForModbus extends ChannelOptionBase
    with ChannelOptionForModbusMappable {
  const ChannelOptionForModbus({
    required this.isRtu,
    required this.unitId,
    required this.transport,
  });

  final bool isRtu;
  final int unitId;

  /// 连接方式：tcp 或 unixsocket
  final ModbusTransportOption transport;
}

@MappableClass(discriminatorValue: 'modbus')
final class ChannelTemplateForModbus extends ChannelTemplateBase
    with ChannelTemplateForModbusMappable {
  const ChannelTemplateForModbus({
    required this.polls,
    this.pushes = const [],
  });

  final List<ModbusPoll> polls;
  final List<ModbusPush> pushes;
}

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

@MappableClass()
final class ModbusPoint with ModbusPointMappable {
  const ModbusPoint({
    required this.to,
    required this.offset,
    this.scale = 1,
    this.length = 1,
    this.endian = ModbusEndianType.abcd,
  this.type = VariableType.uint,
  });

  final String to;
  final int offset;
  final double scale;
  final int length;
  final ModbusEndianType endian;
  final VariableType type;
}

@MappableClass()
final class ModbusPoll with ModbusPollMappable {
  const ModbusPoll({
    required this.intervalMs,
    required this.function,
    required this.begin,
    required this.length,
    required this.mapping,
    this.displayName,
  });

  final String? displayName;
  final int function;
  final int begin;
  final int length;
  final int intervalMs;
  final List<ModbusPoint> mapping;
}

/// Modbus 下发（push）配置（扁平结构）
///
/// 单条 push 即描述“从网关点位[from]取值，按[type/length/endian/scale]
/// 编码后写入功能码[function]的地址[begin + offset]”。
@MappableClass()
final class ModbusPush with ModbusPushMappable {
  const ModbusPush({
    required this.from,
    required this.function,
    required this.begin,
    this.scale = 1,
    this.length = 1,
    this.endian = ModbusEndianType.abcd,
  this.type = VariableType.uint,
  });

  /// 网关内部点位标识（作为写入源）
  final String from;

  /// 功能码：1=线圈(coil)，3=保持寄存器(holding register)
  final int function;

  /// 起始地址基准
  final int begin;

  /// 缩放（编码前先应用 scale）
  final double scale;

  /// 数据长度（寄存器数量：1/2/4/8，对线圈为1）
  final int length;

  /// 字节序/字交换策略
  final ModbusEndianType endian;

  /// 数据类型（int/uint/float 等）
  final VariableType type;
}

@MappableClass(discriminatorValue: 'tcp')
final class ModbusTcpOption extends ModbusTransportOption
    with ModbusTcpOptionMappable {
  const ModbusTcpOption({required this.host, required this.port});
  final String host;
  final int port;
}

@MappableClass(discriminatorKey: 'type')
sealed class ModbusTransportOption with ModbusTransportOptionMappable {
  const ModbusTransportOption();
}

@MappableEnum(caseStyle: CaseStyle.lowerCase)
enum ModbusTransportType {
  tcp(),
  unixsocket(),
}

@MappableClass(discriminatorValue: 'unixsocket')
final class ModbusUnixSocketOption extends ModbusTransportOption
    with ModbusUnixSocketOptionMappable {
  const ModbusUnixSocketOption({required this.path});
  final String path;
}
