import 'dart:async';

import 'package:anyio_modbus/modbus_client.dart';
import 'package:anyio_template/service.dart';
import 'package:anyio_template/src/point.dart';
import 'package:anyio_template/util.dart';

import 'template.dart';

final class ChannelSessionForModbus
    extends ChannelSessionBase<ModbusDeviceExt, ModbusTemplate> {
  ChannelSessionForModbus(
    this.deviceId, {
    required this.transport,
    required this.channelOption,
    required this.templateOption,
  }) : client = ModbusClient(
         transport.read,
         transport.write,
         isRtu: channelOption.isRtu,
       ) {
    for (final pool in templateOption.polls) {
      poolMap[pool] = Timer.periodic(
        Duration(milliseconds: pool.intervalTime),
        (_) => _poll(pool),
      );
    }
    // 监听写入事件，触发 _write
    writeController.stream.listen(_write);
  }

  final String deviceId;

  final ModbusClient client;

  final TransportSession transport;
  final ModbusDeviceExt channelOption;
  final ModbusTemplate templateOption;

  final poolMap = <ModbusPoll, Timer>{};

  final readController = StreamController<Point>();
  final writeController = StreamController<Point>();

  int get _unitId => channelOption.unitId;

  @override
  Stream<Point> get read => readController.stream;

  @override
  Sink<Point> get write => writeController;

  Future<void> _write(Point point) async {}

  Future<void> _poll(ModbusPoll poll) async {
    List<dynamic>? reads;

    try {
      switch (poll.function) {
        case 1:
          reads = await client.readCoils(_unitId, poll.address, poll.length);
        case 2:
          reads = await client.readDiscreteInputs(
            _unitId,
            poll.address,
            poll.length,
          );
        case 3:
          reads = await client.readHoldingRegisters(
            _unitId,
            poll.address,
            poll.length,
          );
        case 4:
          reads = await client.readInputRegisters(
            _unitId,
            poll.address,
            poll.length,
          );
      }
    } on Exception {
      // ...existing code...
    }

    if (reads != null) {
      for (final point in templateOption.reads) {
        // 确保整段点位落在轮询窗口内
        if (point.address >= poll.address &&
            point.address + point.length <= poll.address + poll.length) {
          final start = point.address - poll.address;
          final end = start + point.length;
          final temp = reads.sublist(start, end);

          dynamic value;

          switch (point.type) {
            case ModbusPointType.bool:
              value = ValueListHelper.readBool(temp);
            case ModbusPointType.int:
              value = ValueListHelper.readInt(
                temp,
                point.length,
                point.endian.endian,
              );
            case ModbusPointType.uint:
              value = ValueListHelper.readUint(
                temp,
                point.length,
                point.endian.endian,
              );
            case ModbusPointType.float:
              value = ValueListHelper.readFloat(
                temp,
                point.length,
                point.endian.endian,
              );
          }

          readController.add((
            PointId(deviceId, point.tag),
            PointValue.fromValue(value, DateTime.now().millisecondsSinceEpoch),
          ));
        }
      }
    }
  }
}

final class ChannelFactoryForModbus
    extends
        ChannelFactoryBase<
          ModbusDeviceExt,
          ModbusTemplate,
          ChannelSessionForModbus
        > {
  @override
  ChannelSessionForModbus create(
    String deviceId, {
    required TransportSession transport,
    required ModbusDeviceExt channelOption,
    required ModbusTemplate templateOption,
  }) {
    return ChannelSessionForModbus(
      deviceId,
      transport: transport,
      channelOption: channelOption,
      templateOption: templateOption,
    );
  }

  @override
  ModbusDeviceExt loadChannelOption(Map<dynamic, dynamic> json) {
    return ModbusDeviceExt.fromJson(json);
  }

  @override
  ModbusTemplate loadTemplateOption(Map<dynamic, dynamic> json) {
    return ModbusTemplate.fromJson(json);
  }
}
