// ignore_for_file: avoid_print example

import 'dart:async';
import 'dart:io';

import 'package:anyio_modbus/modbus_server.dart';

final data = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];


void main() async {
  final server = await ServerSocket.bind(InternetAddress.anyIPv4, 8888);

  server.listen((socket) async {
    print('new client connect ${socket.address}:${socket.port}');

    final modbus = ModbusServer(socket, socket);

    print('client deconnect ${socket.address}:${socket.port}');
  });
}
