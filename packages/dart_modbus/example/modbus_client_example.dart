// example
// ignore_for_file: avoid_print, inference_failure_on_instance_creation

import 'dart:async';
import 'dart:io';

import 'package:anyio_modbus/modbus_client.dart';

void main() async {
  print('=== Modbus客户端示例 ===\n');

  final socket = await Socket.connect(InternetAddress.loopbackIPv4, 8888);

  // 创建TCP客户端
  final client = ModbusClient(socket, socket, isRtu: true);

  while (true) {
    final now = DateTime.now();

    print('readHoldingRegisters From 1 To 5 Begin');
    final read1 = await client.readHoldingRegisters(1, 0, 3);
    final read2 = await client.readHoldingRegisters(1, 3, 3);
    print(
      'readHoldingRegisters From 1 To 5 End ${DateTime.now().millisecondsSinceEpoch - now.millisecondsSinceEpoch}',
    );

    print(read1 + read2);

    await Future.delayed(const Duration(seconds: 1));
  }
}
