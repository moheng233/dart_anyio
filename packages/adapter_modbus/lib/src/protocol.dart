import 'dart:async';
import 'dart:typed_data';

import 'package:anyio_modbus/modbus_client.dart';
import 'package:anyio_template/service.dart';
import 'package:anyio_template/util.dart';
import 'package:dart_mappable/dart_mappable.dart';

import 'template.dart';

final class ChannelFactoryForModbus
    extends
        ChannelFactoryBase<
          ChannelOptionForModbus,
          ChannelTemplateForModbus,
          ChannelSessionForModbus
        > {
  @override
  ClassMapperBase<ChannelOptionForModbus> get channelOptionMapper =>
      ChannelOptionForModbusMapper.ensureInitialized();

  @override
  ClassMapperBase<ChannelTemplateForModbus> get templateOptionMapper =>
      ChannelTemplateForModbusMapper.ensureInitialized();

  @override
  ChannelSessionForModbus create(
    String deviceId, {
    required Stream<DeviceBaseEvent> deviceEvent,
    required TransportSession transport,
    required ChannelOptionForModbus channelOption,
    required ChannelTemplateForModbus templateOption,
  }) {
    return ChannelSessionForModbus(
      deviceId,
      write: deviceEvent,
      transport: transport,
      channelOption: channelOption,
      templateOption: templateOption,
    );
  }
}

final class ChannelSessionForModbus
    extends
        ChannelSessionBase<ChannelOptionForModbus, ChannelTemplateForModbus> {
  ChannelSessionForModbus(
    this.deviceId, {
    required super.write,
    required this.transport,
    required this.channelOption,
    required this.templateOption,
  }) : client = ModbusClient(
         transport.read,
         transport.write,
         isRtu: channelOption.isRtu,
       ) {
    write.listen(_write);
  }

  final String deviceId;

  final ModbusClient client;

  final TransportSession transport;
  final ChannelOptionForModbus channelOption;
  final ChannelTemplateForModbus templateOption;

  final poolMap = <ModbusPoll, Timer>{};

  final readController = StreamController<ChannelBaseEvent>();

  @override
  Stream<ChannelBaseEvent> get read => readController.stream;

  int get _unitId => channelOption.unitId;

  @override
  void open() {
    for (final pool in templateOption.polls) {
      poolMap[pool] = Timer.periodic(
        Duration(milliseconds: pool.intervalMs),
        (_) => _poll(pool),
      );
    }
  }

  @override
  void stop() {
    for (final timer in poolMap.values) {
      timer.cancel();
    }

    poolMap.clear();
  }

  bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.toLowerCase().trim();
      if (v == 'true' || v == '1' || v == 'on') return true;
      if (v == 'false' || v == '0' || v == 'off') return false;
    }
    throw FormatException('Unsupported bool value: $value');
  }

  List<int> _bytesToRegisters(Uint8List bytes) {
    assert(bytes.length % 2 == 0);
    final regs = <int>[];
    for (var i = 0; i < bytes.length; i += 2) {
      regs.add(((bytes[i] & 0xFF) << 8) | (bytes[i + 1] & 0xFF));
    }
    return regs;
  }

  List<int> _encodeFloat(ModbusPoint point, Object? value) {
    final numVal = _toNum(value).toDouble();
    final endian = point.endian.endian;
    final swap = point.endian.swap;

    if (point.length == 4) {
      // double (8 bytes)
      final d = ByteData(8)..setFloat64(0, numVal, endian);
      final bytes = Uint8List.view(d.buffer);
      return _bytesToRegisters(bytes);
    }

    // float32 (4 bytes), with optional swap
    final bytes = Uint8List(4);
    if (!swap) {
      final d = ByteData(4)..setFloat32(0, numVal, endian);
      final t = Uint8List.view(d.buffer);
      bytes.setAll(0, [t[0], t[1], t[2], t[3]]);
    } else {
      // Build big-endian bytes then rearrange per swap rules
      final d = ByteData(4)..setFloat32(0, numVal, Endian.big);
      final t = Uint8List.view(d.buffer);
      if (endian == Endian.big) {
        // BADC
        bytes.setAll(0, [t[1], t[0], t[3], t[2]]);
      } else {
        // CDAB
        bytes.setAll(0, [t[2], t[3], t[0], t[1]]);
      }
    }
    return _bytesToRegisters(bytes);
  }

  List<int> _encodeInt(
    ModbusPoint point,
    Object? value, {
    required bool signed,
  }) {
    final intVal = _toInt(value);
    final endian = point.endian.endian;
    final swap = point.endian.swap;
    final regs = <int>[];

    if (point.length == 1) {
      final data = ByteData(2);
      if (signed) {
        data.setInt16(0, intVal, endian);
      } else {
        data.setUint16(0, intVal, endian);
      }
      final b = Uint8List.view(data.buffer);
      regs.add((b[0] << 8) | b[1]);
      return regs;
    }

    if (point.length == 2) {
      // 32-bit
      final bytes = Uint8List(4);
      if (!swap) {
        final d = ByteData(4);
        if (signed) {
          d.setInt32(0, intVal, endian);
        } else {
          d.setUint32(0, intVal, endian);
        }
        final t = Uint8List.view(d.buffer);
        bytes.setAll(0, [t[0], t[1], t[2], t[3]]);
      } else {
        // Build big-endian bytes of value, then rearrange per swap rules
        final d = ByteData(4)..setUint32(0, intVal, Endian.big);
        final t = Uint8List.view(d.buffer);
        if (endian == Endian.big) {
          // BADC -> [t1,t0,t3,t2]
          bytes.setAll(0, [t[1], t[0], t[3], t[2]]);
        } else {
          // CDAB -> [t2,t3,t0,t1]
          bytes.setAll(0, [t[2], t[3], t[0], t[1]]);
        }
      }
      return _bytesToRegisters(bytes);
    }

    if (point.length == 4) {
      // 64-bit
      final d = ByteData(8);
      if (signed) {
        d.setInt64(0, intVal, endian);
      } else {
        d.setUint64(0, intVal, endian);
      }
      final bytes = Uint8List.view(d.buffer);
      return _bytesToRegisters(bytes);
    }

    // Unsupported length
    throw UnsupportedError('Unsupported int length: ${point.length}');
  }

  List<int> _encodeToRegisters(ModbusPoint point, Object? value) {
    try {
      switch (point.type) {
        case PointType.bool:
          final v = _asBool(value) ? 1 : 0;
          return [v & 0xFFFF];
        case PointType.int:
          return _encodeInt(point, value, signed: true);
        case PointType.uint:
          return _encodeInt(point, value, signed: false);
        case PointType.float:
          return _encodeFloat(point, value);
      }
    } on Exception {
      return const <int>[];
    }
  }

  Future<void> _poll(ModbusPoll poll) async {
    List<dynamic>? reads;

    try {
      switch (poll.function) {
        case 1:
          reads = await client.readCoils(_unitId, poll.begin, poll.length);
        case 2:
          reads = await client.readDiscreteInputs(
            _unitId,
            poll.begin,
            poll.length,
          );
        case 3:
          reads = await client.readHoldingRegisters(
            _unitId,
            poll.begin,
            poll.length,
          );
        case 4:
          reads = await client.readInputRegisters(
            _unitId,
            poll.begin,
            poll.length,
          );
      }
    } on Exception catch (_) {}
    if (reads == null) {
      readController.add(
        ChannelUpdateEvent(
          deviceId,
          poll.mapping
              .map((e) => Point(deviceId, e.to, null))
              .toList(growable: true),
        ),
      );
      return;
    }

    final updates = <Point>[];

    if (poll.function == 1 || poll.function == 2) {
      final view = reads.cast<bool>();
      for (final point in poll.mapping) {
        try {
          final value = view[point.offset];
          updates.add(Point(deviceId, point.to, value));
        } on Exception catch (_) {
          updates.add(Point(deviceId, point.to, null));
        }
      }
    } else {
      // register based
      final registers = reads.cast<int>();
      final bytes = Uint8List(registers.length * 2);
      final view = ByteData.view(bytes.buffer);
      for (var i = 0; i < registers.length; i++) {
        view.setUint16(i * 2, registers[i]);
      }

      for (final point in poll.mapping) {
        try {
          final endian = point.endian.endian;
          final swap = point.endian.swap;
          final offset = point.offset * 2;
          final value = switch (point.type) {
            PointType.bool => registers[point.offset] != 0,
            PointType.int => switch (point.length) {
              2 => view.getUint32Swap(offset, endian: endian, swap: swap),
              4 => view.getInt64(offset, endian),
              int() => view.getInt16(offset, endian),
            },
            PointType.uint => switch (point.length) {
              2 => view.getUint32Swap(offset, endian: endian, swap: swap),
              4 => view.getUint64(offset, endian),
              int() => view.getUint16(offset, endian),
            },
            PointType.float => switch (point.length) {
              4 => view.getFloat64(offset, endian),
              int() => view.getFloat32Swap(offset, endian: endian, swap: swap),
            },
          };
          updates.add(Point(deviceId, point.to, value));
        } on Exception catch (_) {
          updates.add(Point(deviceId, point.to, null));
        }
      }
    }

    readController.add(ChannelUpdateEvent(deviceId, updates));
  }

  int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.parse(value);
    throw FormatException('Unsupported int value: $value');
  }

  num _toNum(Object? value) {
    if (value is num) return value;
    if (value is String) return num.parse(value);
    throw FormatException('Unsupported num value: $value');
  }

  Future<void> _write(DeviceBaseEvent event) async {
    if (event is! DeviceWriteEvent) return;
    if (event.deviceId != deviceId) return;

    // Find writable mapping for tagId
    ModbusPoll? targetPoll;
    ModbusPoint? targetPoint;
    for (final poll in templateOption.polls) {
      for (final m in poll.mapping) {
        if (m.to == event.tagId && m.access.write) {
          targetPoll = poll;
          targetPoint = m;
          break;
        }
      }
      if (targetPoint != null) break;
    }

    if (targetPoll == null || targetPoint == null) {
      readController.add(
        ChannelWriteResultEvent(deviceId, event.tagId, success: false),
      );
      return;
    }

    final addr = targetPoll.begin + targetPoint.offset;

    try {
      switch (targetPoll.function) {
        case 1: // Coils
          final ok = await _writeCoil(addr, event.value);
          readController.add(
            ChannelWriteResultEvent(deviceId, event.tagId, success: ok),
          );
        case 3: // Holding registers
          final ok = await _writeRegisters(targetPoint, addr, event.value);
          readController.add(
            ChannelWriteResultEvent(deviceId, event.tagId, success: ok),
          );
        case 2: // Discrete inputs - read-only
        case 4: // Input registers - read-only
          readController.add(
            ChannelWriteResultEvent(deviceId, event.tagId, success: false),
          );
      }
    } on Exception catch (_) {
      readController.add(
        ChannelWriteResultEvent(deviceId, event.tagId, success: false),
      );
    }
  }

  Future<bool> _writeCoil(int addr, Object? value) async {
    final v = _asBool(value);
    final ok = await client.writeSingleCoil(_unitId, addr, v);
    return ok == v; // device echoes written value
  }

  Future<bool> _writeRegisters(
    ModbusPoint point,
    int addr,
    Object? value,
  ) async {
    final regs = _encodeToRegisters(point, value);
    if (regs.isEmpty) return false;

    if (regs.length == 1) {
      final written = await client.writeHoldingRegister(_unitId, addr, regs[0]);
      return written == regs[0];
    } else {
      final count = await client.writeMultipleRegisters(_unitId, addr, regs);
      return count == regs.length;
    }
  }
}
