// ignore_for_file: avoid_print example

import 'dart:async';
import 'dart:io';

import 'package:anyio_modbus_slave/modbus_slave.dart';

final data = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

class ModbusServer
    extends StreamTransformerBase<ModbusFrameRequest, ModbusFrameResponse> {
  @override
  Stream<ModbusFrameResponse> bind(Stream<ModbusFrameRequest> stream) async* {
    await for (final req in stream) {
      switch (req) {
        case ReadHoldingRegistersRequest():
          print('read ${req.startAddress} count ${req.quantity}');
          yield req.response(
            data.sublist(req.startAddress, req.startAddress + req.quantity),
          );
        case WriteSingleRegisterRequest():
          print('write ${req.address} for ${req.value}');
          data[req.address] = req.value;

          yield req.response();
      }
    }
  }
}

void main() async {
  final server = await ServerSocket.bind(InternetAddress.anyIPv4, 8888);

  server.listen((socket) async {
    print('new client connect ${socket.address}:${socket.port}');

    final _ = await socket
        .transform(ModbusRequestTransformer())
        .transform(ModbusServer())
        .transform(ModbusResponseTransformer())
        .transform(Uint8ListToIntListTransformer())
        .pipe(socket);

    print('client deconnect ${socket.address}:${socket.port}');
  });
}
