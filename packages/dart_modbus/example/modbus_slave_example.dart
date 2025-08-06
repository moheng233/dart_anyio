// ignore_for_file: avoid_print example

import 'dart:async';
import 'dart:io';

import 'package:anyio_modbus/modbus_slave.dart';

final data = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

class ModbusServer
    extends StreamTransformerBase<ModbusRequestPacket, ModbusResponsePacket> {
  @override
  Stream<ModbusResponsePacket> bind(Stream<ModbusRequestPacket> stream) async* {
    await for (final req in stream) {
      final pdu = req.pdu;

      switch (pdu) {
        case ReadHoldingRegistersRequest():
          print('read ${pdu.startAddress} count ${pdu.quantity}');
          yield ModbusResponsePacket(
            req.unitId,
            pdu.response(
              data.sublist(pdu.startAddress, pdu.startAddress + pdu.quantity),
            ),
            req.transactionId,
          );
        case WriteSingleRegisterRequest():
          print('write ${pdu.address} for ${pdu.value}');
          data[pdu.address] = pdu.value;

          yield ModbusResponsePacket(
            req.unitId,
            pdu.response(),
            req.transactionId,
          );

        case _:
          yield ModbusResponsePacket(
            req.unitId,
            const ModbusPDUResponse.error(0),
            req.transactionId,
          );
      }
    }
  }
}

void main() async {
  final server = await ServerSocket.bind(InternetAddress.anyIPv4, 8888);

  server.listen((socket) async {
    print('new client connect ${socket.address}:${socket.port}');

    final _ = await socket
        .transform(ModbusTcpRequestParser())
        .transform(ModbusServer())
        .transform(ModbusTcpResponseSerializer())
        .transform(Uint8ListToIntListTransformer())
        .pipe(socket);

    print('client deconnect ${socket.address}:${socket.port}');
  });
}
