import 'dart:typed_data';

import 'frame.dart';

/// Modbus PDU处理器
/// 负责PDU的解析和序列化，供TCP和RTU转换器共享使用
class ModbusPduProcessor {
  /// Modbus 协议字段使用的大端字节序 (Big-Endian / Network Byte Order)
  static const Endian _endian = Endian.big;
  // =========================
  // Request Parsing / Helpers
  // =========================
  /// 从字节数据解析请求PDU
  static ModbusPDURequest parseRequest(int functionCode, Uint8List data) {
    final dataView = ByteData.view(data.buffer);

    return switch (functionCode) {
      // 0x01 - Read Coils
      0x01 => ModbusPDURequest.readCoils(
        dataView.getUint16(0, _endian),
        dataView.getUint16(2, _endian),
      ),
      // 0x02 - Read Discrete Inputs
      0x02 => ModbusPDURequest.readDiscreteInputs(
        dataView.getUint16(0, _endian),
        dataView.getUint16(2, _endian),
      ),
      // 0x03 - Read Holding Registers
      0x03 => ModbusPDURequest.readHoldingRegisters(
        dataView.getUint16(0, _endian),
        dataView.getUint16(2, _endian),
      ),
      // 0x04 - Read Input Registers
      0x04 => ModbusPDURequest.readInputRegisters(
        dataView.getUint16(0, _endian),
        dataView.getUint16(2, _endian),
      ),
      // 0x05 - Write Single Coil
      0x05 => ModbusPDURequest.writeSingleCoil(
        dataView.getUint16(0, _endian),
        dataView.getUint16(2, _endian) ==
            0xFF00, // 0xFF00 = true, 0x0000 = false
      ),
      // 0x06 - Write Single Register
      0x06 => ModbusPDURequest.writeSingleRegister(
        dataView.getUint16(0, _endian),
        dataView.getUint16(2, _endian),
      ),
      // 0x0F - Write Multiple Coils
      0x0F => _parseWriteMultipleCoils(data),
      // 0x10 - Write Multiple Registers
      0x10 => _parseWriteMultipleRegisters(data),
      _ => throw ModbusException(
        'Unsupported function code',
        'Function code 0x${functionCode.toRadixString(16)} is not supported',
      ),
    };
  }

  /// 获取请求功能码
  static int getRequestFunctionCode(ModbusPDURequest request) {
    return switch (request) {
      ReadCoilsRequest() => 0x01,
      ReadDiscreteInputsRequest() => 0x02,
      ReadHoldingRegistersRequest() => 0x03,
      ReadInputRegistersRequest() => 0x04,
      WriteSingleCoilRequest() => 0x05,
      WriteSingleRegisterRequest() => 0x06,
      WriteMultipleCoilsRequest() => 0x0F,
      WriteMultipleRegistersRequest() => 0x10,
    };
  }

  /// 计算请求主体数据长度（不含unitId与functionCode）
  static int calculateRequestBodyLength(ModbusPDURequest request) {
    return switch (request) {
      ReadCoilsRequest() => 4, // startAddr + quantity
      ReadDiscreteInputsRequest() => 4,
      ReadHoldingRegistersRequest() => 4,
      ReadInputRegistersRequest() => 4,
      WriteSingleCoilRequest() => 4, // addr + value
      WriteSingleRegisterRequest() => 4,
      WriteMultipleCoilsRequest() =>
        5 + _calculateCoilsByteCount(request.values.length),
      WriteMultipleRegistersRequest() => 5 + (request.values.length * 2),
    };
  }

  /// 填充请求数据（不含unitId与functionCode）
  static void fillRequestData(
    ByteData view,
    ModbusPDURequest request,
    int offset,
  ) {
    switch (request) {
      case ReadCoilsRequest():
        view.setUint16(offset, request.startAddress, _endian);
        view.setUint16(offset + 2, request.quantity, _endian);
      case ReadDiscreteInputsRequest():
        view.setUint16(offset, request.startAddress, _endian);
        view.setUint16(offset + 2, request.quantity, _endian);
      case ReadHoldingRegistersRequest():
        view.setUint16(offset, request.startAddress, _endian);
        view.setUint16(offset + 2, request.quantity, _endian);
      case ReadInputRegistersRequest():
        view.setUint16(offset, request.startAddress, _endian);
        view.setUint16(offset + 2, request.quantity, _endian);
      case WriteSingleCoilRequest():
        view.setUint16(offset, request.address, _endian);
        view.setUint16(offset + 2, request.value ? 0xFF00 : 0x0000, _endian);
      case WriteSingleRegisterRequest():
        view.setUint16(offset, request.address, _endian);
        view.setUint16(offset + 2, request.value, _endian);
      case WriteMultipleCoilsRequest():
        view.setUint16(offset, request.startAddress, _endian);
        view.setUint16(offset + 2, request.values.length, _endian);
        final byteCount = _calculateCoilsByteCount(request.values.length);
        view.setUint8(offset + 4, byteCount);
        _packCoilsToBytes(view, request.values, offset + 5);
      case WriteMultipleRegistersRequest():
        view.setUint16(offset, request.startAddress, _endian);
        view.setUint16(offset + 2, request.values.length, _endian);
        view.setUint8(offset + 4, request.values.length * 2);
        for (var i = 0; i < request.values.length; i++) {
          view.setUint16(offset + 5 + i * 2, request.values[i], _endian);
        }
    }
  }

  // =========================
  // Response Parsing / Helpers
  // =========================

  /// 解析响应数据（根据功能码与数据，不含unitId）
  static ModbusPDUResponse parseResponse(int functionCode, Uint8List data) {
    final dataView = ByteData.view(data.buffer);

    // 异常响应：功能码最高位 + 原功能码
    if (functionCode >= 0x80) {
      return ModbusPDUResponse.error(dataView.getUint8(0));
    }

    return switch (functionCode) {
      0x01 => _parseCoilsResponse(data),
      0x02 => _parseDiscreteInputsResponse(data),
      0x03 => _parseHoldingRegistersResponse(data),
      0x04 => _parseInputRegistersResponse(data),
      0x05 => _parseSingleCoilResponse(data),
      0x06 => _parseSingleRegisterResponse(data),
      0x0F => _parseMultipleCoilsResponse(data),
      0x10 => _parseMultipleRegistersResponse(data),
      _ => throw ModbusException(
        'Unsupported function code',
        'Function code 0x${functionCode.toRadixString(16)} is not supported',
      ),
    };
  }

  static ModbusPDUResponse _parseCoilsResponse(Uint8List data) {
    final byteCount = data[0];
    final coilData = data.sublist(1, 1 + byteCount);
    final coils = <bool>[];
    for (var byteIndex = 0; byteIndex < byteCount; byteIndex++) {
      final byte = coilData[byteIndex];
      for (var bitIndex = 0; bitIndex < 8; bitIndex++) {
        coils.add((byte & (1 << bitIndex)) != 0);
      }
    }
    return ModbusPDUResponse.readCoils(coils);
  }

  static ModbusPDUResponse _parseDiscreteInputsResponse(Uint8List data) {
    final byteCount = data[0];
    final inputData = data.sublist(1, 1 + byteCount);
    final inputs = <bool>[];
    for (var byteIndex = 0; byteIndex < byteCount; byteIndex++) {
      final byte = inputData[byteIndex];
      for (var bitIndex = 0; bitIndex < 8; bitIndex++) {
        inputs.add((byte & (1 << bitIndex)) != 0);
      }
    }
    return ModbusPDUResponse.readDiscreteInputs(inputs);
  }

  static ModbusPDUResponse _parseHoldingRegistersResponse(Uint8List data) {
    final byteCount = data[0];
    final registerData = data.sublist(1, 1 + byteCount);
    final registers = <int>[];
    for (var i = 0; i < byteCount; i += 2) {
      registers.add(ByteData.view(registerData.buffer).getUint16(i, _endian));
    }
    return ModbusPDUResponse.readHoldingRegisters(registers);
  }

  static ModbusPDUResponse _parseInputRegistersResponse(Uint8List data) {
    final byteCount = data[0];
    final registerData = data.sublist(1, 1 + byteCount);
    final registers = <int>[];
    for (var i = 0; i < byteCount; i += 2) {
      registers.add(ByteData.view(registerData.buffer).getUint16(i, _endian));
    }
    return ModbusPDUResponse.readInputRegisters(registers);
  }

  static ModbusPDUResponse _parseSingleCoilResponse(Uint8List data) {
    final dataView = ByteData.view(data.buffer);
    final address = dataView.getUint16(0, _endian);
    final value = dataView.getUint16(2, _endian) == 0xFF00;
    return ModbusPDUResponse.writeSingleCoil(address, value);
  }

  static ModbusPDUResponse _parseSingleRegisterResponse(Uint8List data) {
    final dataView = ByteData.view(data.buffer);
    final address = dataView.getUint16(0, _endian);
    final value = dataView.getUint16(2, _endian);
    return ModbusPDUResponse.writeSingleRegister(address, value);
  }

  static ModbusPDUResponse _parseMultipleCoilsResponse(Uint8List data) {
    final dataView = ByteData.view(data.buffer);
    final startAddress = dataView.getUint16(0, _endian);
    final quantity = dataView.getUint16(2, _endian);
    return ModbusPDUResponse.writeMultipleCoils(startAddress, quantity);
  }

  static ModbusPDUResponse _parseMultipleRegistersResponse(Uint8List data) {
    final dataView = ByteData.view(data.buffer);
    final startAddress = dataView.getUint16(0, _endian);
    final quantity = dataView.getUint16(2, _endian);
    return ModbusPDUResponse.writeMultipleRegisters(startAddress, quantity);
  }

  /// 解析写多个线圈请求
  static ModbusPDURequest _parseWriteMultipleCoils(Uint8List data) {
    final dataView = ByteData.view(data.buffer);
    final startAddress = dataView.getUint16(0, _endian);
    final quantity = dataView.getUint16(2, _endian);
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
      values.add(dataView.getUint16(5 + i * 2, _endian));
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
          view.setUint16(offset + 1 + i * 2, response.values[i], _endian);
        }
      case ReadInputRegistersResponse():
        view.setUint8(offset, response.values.length * 2);
        for (var i = 0; i < response.values.length; i++) {
          view.setUint16(offset + 1 + i * 2, response.values[i], _endian);
        }
      case WriteSingleCoilResponse():
        view.setUint16(offset, response.address, _endian);
        view.setUint16(offset + 2, response.value ? 0xFF00 : 0x0000, _endian);
      case WriteSingleRegisterResponse():
        view.setUint16(offset, response.address, _endian);
        view.setUint16(offset + 2, response.value, _endian);
      case WriteMultipleCoilsResponse():
        view.setUint16(offset, response.startAddress, _endian);
        view.setUint16(offset + 2, response.quantity, _endian);
      case WriteMultipleRegistersResponse():
        view.setUint16(offset, response.startAddress, _endian);
        view.setUint16(offset + 2, response.quantity, _endian);
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
