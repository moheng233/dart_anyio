// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import '../lib/src/frame.dart';
import '../lib/src/client_transformers.dart';

class ModbusClientExample {
  late Socket _socket;
  late StreamController<ModbusRequestPacket> _requestController;
  late Stream<ModbusResponsePacket> _responseStream;
  final ModbusClient _client;
  int _transactionId = 0;

  ModbusClientExample({bool isRtu = false}) : _client = ModbusClient(isRtu: isRtu);

  /// 连接到Modbus服务器
  Future<void> connect(String host, int port) async {
    _socket = await Socket.connect(host, port);
    print('Connected to Modbus server at $host:$port');

    // 设置请求控制器
    _requestController = StreamController<ModbusRequestPacket>();

    // 设置数据流管道：请求 -> 字节 -> 网络 -> 字节 -> 响应
    _requestController.stream
        .transform(_client.requestTransformer)
        .listen((bytes) {
      print('Sending: ${bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
      _socket.add(bytes);
    });

    // 设置响应流
    _responseStream = _socket.transform(_client.responseTransformer);
  }

  /// 关闭连接
  Future<void> disconnect() async {
    await _requestController.close();
    await _socket.close();
    print('Disconnected from Modbus server');
  }

  /// 发送请求并等待响应
  Future<ModbusResponsePacket> sendRequest(ModbusPDURequest request, int unitId) async {
    final transactionId = _client.isRtu ? null : ++_transactionId;
    
    final requestPacket = _client.isRtu
        ? ModbusClient.createRtuRequest(unitId, request)
        : ModbusClient.createTcpRequest(unitId, request, transactionId!);

    print('Sending request: $request');
    
    // 发送请求
    _requestController.add(requestPacket);

    // 等待响应（简化版本，实际应用中需要匹配transactionId）
    final response = await _responseStream.first;
    print('Received response: ${response.pdu}');
    
    return response;
  }

  /// 读取保持寄存器
  Future<List<int>> readHoldingRegisters(int unitId, int startAddress, int quantity) async {
    final request = ModbusPDURequest.readHoldingRegisters(startAddress, quantity);
    final response = await sendRequest(request, unitId);
    
    switch (response.pdu) {
      case ReadHoldingRegistersResponse():
        final holdingResponse = response.pdu as ReadHoldingRegistersResponse;
        return holdingResponse.values;
      case ModbusErrorResponse():
        final errorResponse = response.pdu as ModbusErrorResponse;
        throw Exception('Modbus error: ${errorResponse.errorCode}');
      default:
        throw Exception('Unexpected response type: ${response.pdu}');
    }
  }

  /// 写入单个寄存器
  Future<void> writeSingleRegister(int unitId, int address, int value) async {
    final request = ModbusPDURequest.writeSingleRegister(address, value);
    final response = await sendRequest(request, unitId);
    
    switch (response.pdu) {
      case WriteSingleRegisterResponse():
        print('Successfully wrote value $value to register $address');
      case ModbusErrorResponse():
        final errorResponse = response.pdu as ModbusErrorResponse;
        throw Exception('Modbus error: ${errorResponse.errorCode}');
      default:
        throw Exception('Unexpected response type: ${response.pdu}');
    }
  }

  /// 读取线圈
  Future<List<bool>> readCoils(int unitId, int startAddress, int quantity) async {
    final request = ModbusPDURequest.readCoils(startAddress, quantity);
    final response = await sendRequest(request, unitId);
    
    switch (response.pdu) {
      case ReadCoilsResponse():
        final coilResponse = response.pdu as ReadCoilsResponse;
        return coilResponse.values.take(quantity).toList();
      case ModbusErrorResponse():
        final errorResponse = response.pdu as ModbusErrorResponse;
        throw Exception('Modbus error: ${errorResponse.errorCode}');
      default:
        throw Exception('Unexpected response type: ${response.pdu}');
    }
  }

  /// 写入单个线圈
  Future<void> writeSingleCoil(int unitId, int address, bool value) async {
    final request = ModbusPDURequest.writeSingleCoil(address, value);
    final response = await sendRequest(request, unitId);
    
    switch (response.pdu) {
      case WriteSingleCoilResponse():
        print('Successfully wrote coil $address to ${value ? "ON" : "OFF"}');
      case ModbusErrorResponse():
        final errorResponse = response.pdu as ModbusErrorResponse;
        throw Exception('Modbus error: ${errorResponse.errorCode}');
      default:
        throw Exception('Unexpected response type: ${response.pdu}');
    }
  }

  /// 写入多个寄存器
  Future<void> writeMultipleRegisters(int unitId, int startAddress, List<int> values) async {
    final request = ModbusPDURequest.writeMultipleRegisters(startAddress, values);
    final response = await sendRequest(request, unitId);
    
    switch (response.pdu) {
      case WriteMultipleRegistersResponse():
        print('Successfully wrote ${values.length} registers starting at $startAddress');
      case ModbusErrorResponse():
        final errorResponse = response.pdu as ModbusErrorResponse;
        throw Exception('Modbus error: ${errorResponse.errorCode}');
      default:
        throw Exception('Unexpected response type: ${response.pdu}');
    }
  }
}

void main() async {
  print('=== Modbus客户端示例 ===\n');

  // 创建TCP客户端
  final client = ModbusClientExample(isRtu: false);

  try {
    // 连接到服务器（假设有一个Modbus服务器运行在8888端口）
    await client.connect('127.0.0.1', 8888);

    // 示例操作
    print('1. 读取保持寄存器 0-4:');
    try {
      final values = await client.readHoldingRegisters(1, 0, 5);
      print('   值: $values\n');
    } catch (e) {
      print('   错误: $e\n');
    }

    print('2. 写入寄存器 5 = 12345:');
    try {
      await client.writeSingleRegister(1, 5, 12345);
      print('   写入成功\n');
    } catch (e) {
      print('   错误: $e\n');
    }

    print('3. 读取线圈 0-7:');
    try {
      final coils = await client.readCoils(1, 0, 8);
      print('   线圈状态: $coils\n');
    } catch (e) {
      print('   错误: $e\n');
    }

    print('4. 写入多个寄存器 10-12:');
    try {
      await client.writeMultipleRegisters(1, 10, [100, 200, 300]);
      print('   写入成功\n');
    } catch (e) {
      print('   错误: $e\n');
    }

  } catch (e) {
    print('连接失败: $e');
  } finally {
    await client.disconnect();
  }

  print('=== 示例完成 ===');
}
