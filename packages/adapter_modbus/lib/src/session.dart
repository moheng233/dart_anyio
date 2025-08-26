import 'dart:async';
import 'dart:typed_data';

import 'package:anyio_modbus/modbus_client.dart';
import 'package:anyio_template/service.dart';
import 'package:anyio_template/util.dart';

import 'template.dart';
import 'util.dart';

final class ChannelSessionForModbus {
  ChannelSessionForModbus(
    this.deviceId, {
    required Stream<DeviceBaseEvent> write,
    required this.client,
    required this.channelOption,
    required this.templateOption,
  }) : _writeStream = write {
    _writeStream.listen(_write);
  }

  final String deviceId;

  final ModbusClient client;

  final ChannelOptionForModbus channelOption;
  final ChannelTemplateForModbus templateOption;

  final poolTimer = <ModbusPoll, Timer>{};

  final readController = StreamController<ChannelBaseEvent>();
  final Stream<DeviceBaseEvent> _writeStream;

  Stream<ChannelBaseEvent> get read => readController.stream;

  int get _unitId => channelOption.unitId;

  void open() {
    for (final pool in templateOption.polls) {
      poolTimer[pool] = Timer.periodic(
        Duration(milliseconds: pool.intervalMs),
        (_) => _poll(pool),
      );
    }
  }

  void stop() {
    for (final timer in poolTimer.values) {
      timer.cancel();
    }

    poolTimer.clear();
  }

  Future<void> _poll(ModbusPoll poll) async {
    List<dynamic>? reads;

    final startTime = DateTime.now();

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
              .map((e) => Variable(deviceId, e.to, null))
              .toList(growable: true),
        ),
      );
      return;
    }

  final updates = <Variable>[];

    if (poll.function == 1 || poll.function == 2) {
      final view = reads.cast<bool>();
      for (final point in poll.mapping) {
        try {
          final value = view[point.offset];
          updates.add(Variable(deviceId, point.to, value));
        } on Exception catch (_) {
          updates.add(Variable(deviceId, point.to, null));
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
            VariableType.bool => registers[point.offset] != 0,
            VariableType.int => switch (point.length) {
              2 => view.getUint32Swap(offset, endian: endian, swap: swap),
              4 => view.getInt64(offset, endian),
              int() => view.getInt16(offset, endian),
            },
            VariableType.uint => switch (point.length) {
              2 => view.getUint32Swap(offset, endian: endian, swap: swap),
              4 => view.getUint64(offset, endian),
              int() => view.getUint16(offset, endian),
            },
            VariableType.float => switch (point.length) {
              4 => view.getFloat64(offset, endian),
              int() => view.getFloat32Swap(offset, endian: endian, swap: swap),
            },
          };
          updates.add(Variable(deviceId, point.to, value));
        } on Exception catch (_) {
          updates.add(Variable(deviceId, point.to, null));
        }
      }
    }

    readController.add(ChannelUpdateEvent(deviceId, updates));

    final endTime = DateTime.now();

    readController.add(
      ChannelPerformanceTimeEvent(
        deviceId,
        'poll.${poll.displayName ?? templateOption.polls.indexOf(poll)}',
        diffTime: endTime.difference(startTime),
        startTime: startTime,
        endTime: endTime,
      ),
    );
  }

  Future<void> _write(DeviceBaseEvent event) async {
    if (event is! DeviceActionInvokeEvent) return;
    if (event.deviceId != deviceId) return;

    final startTime = DateTime.now();

    final targetPush = templateOption.pushes.firstWhere(
      (element) => element.from == event.actionId,
    );

    final addr = targetPush.begin;
    try {
      switch (targetPush.function) {
        case 1: // Coils
          final ok = await _writeCoil(addr, event.value);
          readController.add(
            ChannelWritedEvent(deviceId, event.actionId, ok),
          );
        case 3: // Holding registers
          final ok = await _writeRegisters(
            addr,
            targetPush.type,
            targetPush.length,
            targetPush.endian,
            event.value,
          );
          readController.add(
            ChannelWritedEvent(deviceId, event.actionId, ok),
          );
        case 2: // Discrete inputs - read-only
        case 4: // Input registers - read-only
          readController.add(
            ChannelWritedEvent(
              deviceId,
        event.actionId,
              false,
              'function ${targetPush.function} is read-only',
            ),
          );
      }
    } on Exception catch (e) {
      readController.add(
        ChannelWritedEvent(
          deviceId,
      event.actionId,
          false,
          'exception: ${e.runtimeType}',
        ),
      );
    }

    final endTime = DateTime.now();
    readController.add(
      ChannelPerformanceTimeEvent(
        deviceId,
        'write.push.${event.actionId}',
        diffTime: endTime.difference(startTime),
        startTime: startTime,
        endTime: endTime,
      ),
    );
  }

  Future<bool> _writeCoil(int addr, Object? value) async {
    final v = asBool(value);
    final ok = await client.writeSingleCoil(_unitId, addr, v);
    return ok == v; // device echoes written value
  }

  Future<bool> _writeRegisters(
    int addr,
    VariableType type,
    int length,
    ModbusEndianType endianType,
    Object? value,
  ) async {
    // Build registers from value according to spec (type/length/endian/swap)
    List<int> regs;
    try {
      final endian = endianType.endian;
      final swap = endianType.swap;

      switch (type) {
        case VariableType.bool:
          regs = [if (asBool(value)) 1 else 0];
        case VariableType.int:
          {
            final intVal = toInt(value);
            if (length == 1) {
              final d = ByteData(2)..setInt16(0, intVal, endian);
              final b = Uint8List.view(d.buffer);
              regs = [(b[0] << 8) | b[1]];
            } else if (length == 2) {
              final bytes = Uint8List(4);
              if (!swap) {
                final d = ByteData(4)..setInt32(0, intVal, endian);
                final t = Uint8List.view(d.buffer);
                bytes.setAll(0, [t[0], t[1], t[2], t[3]]);
              } else {
                final d = ByteData(4)..setUint32(0, intVal);
                final t = Uint8List.view(d.buffer);
                if (endian == Endian.big) {
                  // BADC -> [t1,t0,t3,t2]
                  bytes.setAll(0, [t[1], t[0], t[3], t[2]]);
                } else {
                  // CDAB -> [t2,t3,t0,t1]
                  bytes.setAll(0, [t[2], t[3], t[0], t[1]]);
                }
              }
              regs = bytesToRegisters(bytes);
            } else if (length == 4) {
              final d = ByteData(8)..setInt64(0, intVal, endian);
              regs = bytesToRegisters(Uint8List.view(d.buffer));
            } else {
              throw UnsupportedError('Unsupported int length: $length');
            }
          }
  case VariableType.uint:
          {
            final intVal = toInt(value);
            if (length == 1) {
              final d = ByteData(2)..setUint16(0, intVal, endian);
              final b = Uint8List.view(d.buffer);
              regs = [(b[0] << 8) | b[1]];
            } else if (length == 2) {
              final bytes = Uint8List(4);
              if (!swap) {
                final d = ByteData(4)..setUint32(0, intVal, endian);
                final t = Uint8List.view(d.buffer);
                bytes.setAll(0, [t[0], t[1], t[2], t[3]]);
              } else {
                final d = ByteData(4)..setUint32(0, intVal);
                final t = Uint8List.view(d.buffer);
                if (endian == Endian.big) {
                  bytes.setAll(0, [t[1], t[0], t[3], t[2]]);
                } else {
                  bytes.setAll(0, [t[2], t[3], t[0], t[1]]);
                }
              }
              regs = bytesToRegisters(bytes);
            } else if (length == 4) {
              final d = ByteData(8)..setUint64(0, intVal, endian);
              regs = bytesToRegisters(Uint8List.view(d.buffer));
            } else {
              throw UnsupportedError('Unsupported uint length: $length');
            }
          }
  case VariableType.float:
          {
            final numVal = toNum(value).toDouble();
            if (length == 4) {
              // double (8 bytes)
              final d = ByteData(8)..setFloat64(0, numVal, endian);
              regs = bytesToRegisters(Uint8List.view(d.buffer));
            } else {
              // float32 (4 bytes), with optional swap
              final bytes = Uint8List(4);
              if (!swap) {
                final d = ByteData(4)..setFloat32(0, numVal, endian);
                final t = Uint8List.view(d.buffer);
                bytes.setAll(0, [t[0], t[1], t[2], t[3]]);
              } else {
                final d = ByteData(4)..setFloat32(0, numVal);
                final t = Uint8List.view(d.buffer);
                if (endian == Endian.big) {
                  // BADC
                  bytes.setAll(0, [t[1], t[0], t[3], t[2]]);
                } else {
                  // CDAB
                  bytes.setAll(0, [t[2], t[3], t[0], t[1]]);
                }
              }
              regs = bytesToRegisters(bytes);
            }
          }
      }
    } on Exception {
      regs = const <int>[];
    }

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
