import 'dart:typed_data';

import 'frame.dart';

/// Modbus PDU处理器
/// 负责PDU的解析和序列化，供TCP和RTU转换器共享使用
class ModbusPduProcessor {
  /// 从字节数据解析请求PDU
  static ModbusPDURequest parseRequest(int functionCode, Uint8List data) {
    final dataView = ByteData.view(data.buffer);

    return switch (functionCode) {
      // 0x01 - Read Coils
      0x01 => ModbusPDURequest.readCoils(
        dataView.getUint16(0),
        dataView.getUint16(2),
      ),
      // 0x02 - Read Discrete Inputs
      0x02 => ModbusPDURequest.readDiscreteInputs(
        dataView.getUint16(0),
        dataView.getUint16(2),
      ),
      // 0x03 - Read Holding Registers
      0x03 => ModbusPDURequest.readHoldingRegisters(
        dataView.getUint16(0),
        dataView.getUint16(2),
      ),
      // 0x04 - Read Input Registers
      0x04 => ModbusPDURequest.readInputRegisters(
        dataView.getUint16(0),
        dataView.getUint16(2),
      ),
      // 0x05 - Write Single Coil
      0x05 => ModbusPDURequest.writeSingleCoil(
        dataView.getUint16(0),
        dataView.getUint16(2) == 0xFF00, // 0xFF00 = true, 0x0000 = false
      ),
      // 0x06 - Write Single Register
      0x06 => ModbusPDURequest.writeSingleRegister(
        dataView.getUint16(0),
        dataView.getUint16(2),
      ),
      // 0x0F - Write Multiple Coils
      0x0F => _parseWriteMultipleCoils(data),
      // 0x10 - Write Multiple Registers
      0x10 => _parseWriteMultipleRegisters(data),
      _ =>
        throw ModbusException(
          'Unsupported function code',
          'Function code 0x${functionCode.toRadixString(16)} is not supported',
        ),
    };
  }

  /// 解析写多个线圈请求
  static ModbusPDURequest _parseWriteMultipleCoils(Uint8List data) {
    final dataView = ByteData.view(data.buffer);
    final startAddress = dataView.getUint16(0);
    final quantity = dataView.getUint16(2);
    final byteCount = dataView.getUint8(4);

    final values = <bool>[];
    for (var byteIndex = 0; byteIndex < byteCount; byteIndex++) {
      final byte = dataView.getUint8(5 + byteIndex);
      for (
        var bitIndex = 0;
        bitIndex < 8 && values.length < quantity;
        bitIndex++
      ) {
        values.add((byte & (1 << bitIndex)) != 0);
      }
    }

    return ModbusPDURequest.writeMultipleCoils(startAddress, values);
  }

  /// 解析写多个寄存器请求
  static ModbusPDURequest _parseWriteMultipleRegisters(Uint8List data) {
    final dataView = ByteData.view(data.buffer);
    final startAddress = dataView.getUint16(0);
    final quantity = dataView.getUint16(2);
    // byteCount = dataView.getUint8(4); // 可以忽略，因为可以从quantity计算

    final values = <int>[];
    for (var i = 0; i < quantity; i++) {
      values.add(dataView.getUint16(5 + i * 2));
    }

    return ModbusPDURequest.writeMultipleRegisters(startAddress, values);
  }

  /// 计算线圈/离散量所需的字节数
  static int _calculateCoilsByteCount(int coilCount) {
    return (coilCount + 7) ~/ 8; // 向上取整
  }

  /// 将线圈布尔值打包成字节
  static void _packCoilsToBytes(ByteData view, List<bool> coils, int offset) {
    final byteCount = _calculateCoilsByteCount(coils.length);
    for (var byteIndex = 0; byteIndex < byteCount; byteIndex++) {
      var byte = 0;
      for (var bitIndex = 0; bitIndex < 8; bitIndex++) {
        final coilIndex = byteIndex * 8 + bitIndex;
        if (coilIndex < coils.length && coils[coilIndex]) {
          byte |= 1 << bitIndex;
        }
      }
      view.setUint8(offset + byteIndex, byte);
    }
  }

  /// 获取响应的功能码
  static int getFunctionCode(ModbusPDUResponse response) {
    return switch (response) {
      ReadCoilsResponse() => 0x01,
      ReadDiscreteInputsResponse() => 0x02,
      ReadHoldingRegistersResponse() => 0x03,
      ReadInputRegistersResponse() => 0x04,
      WriteSingleCoilResponse() => 0x05,
      WriteSingleRegisterResponse() => 0x06,
      WriteMultipleCoilsResponse() => 0x0F,
      WriteMultipleRegistersResponse() => 0x10,
      ModbusErrorResponse() => 0x80, // 错误响应使用0x80 + 原功能码
    };
  }


  /// 计算响应数据长度
  static int calculateResponseDataLength(ModbusPDUResponse response) {
    return switch (response) {
      ReadCoilsResponse() =>
        1 +
            _calculateCoilsByteCount(
              response.values.length,
            ), // byteCount + data
      ReadDiscreteInputsResponse() =>
        1 +
            _calculateCoilsByteCount(
              response.values.length,
            ), // byteCount + data
      ReadHoldingRegistersResponse() =>
        1 + (response.values.length * 2), // byteCount + data
      ReadInputRegistersResponse() =>
        1 + (response.values.length * 2), // byteCount + data
      WriteSingleCoilResponse() => 4, // address + value
      WriteSingleRegisterResponse() => 4, // address + value
      WriteMultipleCoilsResponse() => 4, // startAddress + quantity
      WriteMultipleRegistersResponse() => 4, // startAddress + quantity
      ModbusErrorResponse() => 1, // errorCode
    };
  }

  /// 将响应数据填充到ByteData中
  static void fillResponseData(
    ByteData view,
    ModbusPDUResponse response,
    int offset,
  ) {
    switch (response) {
      case ReadCoilsResponse():
        final byteCount = _calculateCoilsByteCount(response.values.length);
        view.setUint8(offset, byteCount);
        _packCoilsToBytes(view, response.values, offset + 1);
      case ReadDiscreteInputsResponse():
        final byteCount = _calculateCoilsByteCount(response.values.length);
        view.setUint8(offset, byteCount);
        _packCoilsToBytes(view, response.values, offset + 1);
      case ReadHoldingRegistersResponse():
        view.setUint8(offset, response.values.length * 2);
        for (var i = 0; i < response.values.length; i++) {
          view.setUint16(offset + 1 + i * 2, response.values[i]);
        }
      case ReadInputRegistersResponse():
        view.setUint8(offset, response.values.length * 2);
        for (var i = 0; i < response.values.length; i++) {
          view.setUint16(offset + 1 + i * 2, response.values[i]);
        }
      case WriteSingleCoilResponse():
        view.setUint16(offset, response.address);
        view.setUint16(offset + 2, response.value ? 0xFF00 : 0x0000);
      case WriteSingleRegisterResponse():
        view.setUint16(offset, response.address);
        view.setUint16(offset + 2, response.value);
      case WriteMultipleCoilsResponse():
        view.setUint16(offset, response.startAddress);
        view.setUint16(offset + 2, response.quantity);
      case WriteMultipleRegistersResponse():
        view.setUint16(offset, response.startAddress);
        view.setUint16(offset + 2, response.quantity);
      case ModbusErrorResponse():
        view.setUint8(offset, response.errorCode);
    }
  }

  /// 序列化响应PDU为字节数组（不包含unitId和functionCode）
  static Uint8List serializeResponseData(ModbusPDUResponse response) {
    final dataLength = calculateResponseDataLength(response);
    final buffer = Uint8List(dataLength);
    final view = ByteData.view(buffer.buffer);

    fillResponseData(view, response, 0);
    return buffer;
  }
}
