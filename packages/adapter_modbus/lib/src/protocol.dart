import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

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

  void _write(Point point) async {}

  void _poll(ModbusPoll poll) async {
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
    } on Exception catch (e, stack) {}

    if (reads != null) {
      for (final point in templateOption.reads) {
        if (point.address >= poll.address &&
            point.address <= poll.address + poll.length) {
          final temp = reads.sublist(
            poll.address - point.address,
            point.length,
          );

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
    // TODO: implement create
    throw UnimplementedError();
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
