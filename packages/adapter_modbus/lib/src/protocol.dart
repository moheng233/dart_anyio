import 'dart:async';
import 'dart:typed_data';

import 'package:anyio_modbus/modbus_client.dart';
import 'package:anyio_template/service.dart';
import 'package:anyio_template/util.dart';
import 'package:dart_mappable/dart_mappable.dart';

import 'template.dart';

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

  int get _unitId => channelOption.unitId;

  @override
  Stream<ChannelBaseEvent> get read => readController.stream;

  Future<void> _write(DeviceBaseEvent event) async {}

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
    } on Exception {
      // ...existing code...
    }

    if (reads != null) {
      final updates = <Point>[];
      final ts = DateTime.timestamp().millisecondsSinceEpoch;

      if (poll.function == 1 || poll.function == 2) {
        final view = reads.cast<bool>();

        for (final point in poll.points) {
          updates.add(
            Point(
              deviceId,
              point.tag,
              view[point.offset],
            ),
          );
        }
      } else {
        final registers = reads.cast<int>();
        final bytes = Uint8List(registers.length * 2);
        final view = ByteData.view(bytes.buffer);

        for (var i = 0; i < registers.length; i++) {
          view.setUint16(i * 2, registers[i]);
        }

        for (final point in poll.points) {
          final endian = point.endian.endian;
          final swap = point.endian.swap;
          final offset = point.offset * 2;

          final value = switch (point.type) {
            PointType.bool => reads[point.offset] != 0,
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

          updates.add(
            Point(
              deviceId,
              point.tag,
              value,
            ),
          );
        }
      }

      readController.add(ChannelUpdateEvent(deviceId, updates));
    }
  }

  @override
  void open() {
    for (final pool in templateOption.polls) {
      poolMap[pool] = Timer.periodic(
        Duration(milliseconds: pool.intervalTime),
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
}

final class ChannelFactoryForModbus
    extends
        ChannelFactoryBase<
          ChannelOptionForModbus,
          ChannelTemplateForModbus,
          ChannelSessionForModbus
        > {
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

  @override
  ClassMapperBase<ChannelOptionForModbus> get channelOptionMapper =>
      ChannelOptionForModbusMapper.ensureInitialized();

  @override
  ClassMapperBase<ChannelTemplateForModbus> get templateOptionMapper =>
      ChannelTemplateForModbusMapper.ensureInitialized();
}
