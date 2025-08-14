import 'dart:async';

import 'package:anyio_service/src/transports/tcp.dart';
import 'package:anyio_adapter_modbus/src/protocol.dart';
import 'package:anyio_adapter_modbus/src/template.dart';
import 'package:anyio_template/service.dart';

void main(List<String> args) async {
  final transport = TransportForTcpImpl(
    const TransportOptionForTcp('127.0.0.1', 8888),
  );

  await transport.open();

  final writeController = StreamController<DeviceBaseEvent>();

  final channel = ChannelSessionForModbus(
    'test',
    write: writeController.stream,
    transport: transport,
    channelOption: const ChannelOptionForModbus(isRtu: false, unitId: 1),
    templateOption: const ChannelTemplateForModbus(
      polls: [
        ModbusPoll(
          begin: 0,
          length: 5,
          points: [
            ModbusReadPoint(
              tag: 'n1',
              offset: 0,
              type: PointType.int,
              length: 2,
              endian: ModbusEndianType.abcd,
            ),
            ModbusReadPoint(
              tag: 'n2',
              offset: 2,
              type: PointType.int,
              length: 2,
              endian: ModbusEndianType.dcba,
            ),
          ],
          intervalTime: 2000,
          function: 3,
        ),
      ],
      writes: [],
    ),
  );

  channel.read.listen(print);

  channel.open();
}
