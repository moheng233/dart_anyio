import 'dart:async';
import 'dart:typed_data';

import '../frame.dart';
import '../pdu_processor.dart';

/// Modbus RTU请求解析器
/// 将RTU字节流转换为ModbusRequestPacket
class ModbusRtuRequestParser
    extends StreamTransformerBase<Uint8List, ModbusRequestPacket> {
  final _buffer = BytesBuilder();

  @override
  Stream<ModbusRequestPacket> bind(Stream<Uint8List> stream) async* {
    await for (final data in stream) {
      _buffer.add(data);

      // RTU 协议处理
      while (_buffer.length >= 4) {
        // 最小RTU包：unitId + functionCode + 2字节数据
        final bytes = _buffer.toBytes();
        final packetLength = _calculateRtuPacketLength(bytes);

        if (packetLength == null || _buffer.length < packetLength) {
          break;
        }

        final packet = Uint8List.fromList(
          _buffer.takeBytes().sublist(0, packetLength),
        );
        yield _parseRtuRequest(packet);
      }
    }
  }

  /// 解析RTU请求包
  ModbusRequestPacket parseRtuRequest(Uint8List packet) {
    return _parseRtuRequest(packet);
  }

  /// 解析RTU请求包（内部实现）
  ModbusRequestPacket _parseRtuRequest(Uint8List packet) {
    // 验证CRC
    final dataWithoutCrc = packet.sublist(0, packet.length - 2);
    final receivedCrc = ByteData.view(
      packet.buffer,
    ).getUint16(packet.length - 2, Endian.little);
    final calculatedCrc = ModbusCrc.calculate(dataWithoutCrc);

    if (receivedCrc != calculatedCrc) {
      throw ModbusException(
        'CRC check failed',
        'Expected 0x${calculatedCrc.toRadixString(16)}, got 0x${receivedCrc.toRadixString(16)}',
      );
    }

    final unitId = packet[0];
    final functionCodeByte = packet[1];
    final data = packet.sublist(2, packet.length - 2); // 去掉CRC

    final request = ModbusPduProcessor.parseRequest(functionCodeByte, data);

    return ModbusPacket.request(
          unitId,
          request,
          null, // RTU协议没有transactionId
        )
        as ModbusRequestPacket;
  }

  /// 计算RTU包长度
  int? _calculateRtuPacketLength(Uint8List bytes) {
    if (bytes.length < 2) return null;

    final functionCode = bytes[1];
    return switch (functionCode) {
      0x01 => 8,
      // ReadCoils: unitId + functionCode + startAddr + quantity + CRC
      0x02 => 8,
      // ReadDiscreteInputs: unitId + functionCode + startAddr + quantity + CRC
      0x03 => 8,
      // ReadHoldingRegisters: unitId + functionCode + startAddr + quantity + CRC
      0x04 => 8,
      // ReadInputRegisters: unitId + functionCode + startAddr + quantity + CRC
      0x05 => 8,
      // WriteSingleCoil: unitId + functionCode + addr + value + CRC
      0x06 => 8,
      // WriteSingleRegister: unitId + functionCode + addr + value + CRC
      0x0F => bytes.length >= 7 ? 7 + bytes[6] + 2 : null,
      // WriteMultipleCoils: header + byteCount + data + CRC
      0x10 => bytes.length >= 7 ? 7 + bytes[6] + 2 : null,
      // WriteMultipleRegisters: header + byteCount + data + CRC
      _ => null,
    };
  }
}

/// Modbus RTU请求序列化器
/// 将ModbusRequestPacket转换为RTU字节流
class ModbusRtuRequestSerializer
    extends StreamTransformerBase<ModbusRequestPacket, List<int>> {
  @override
  Stream<List<int>> bind(Stream<ModbusRequestPacket> stream) async* {
    await for (final packet in stream) {
      // 只处理RTU包（没有transactionId的包）
      if (packet.transactionId == null) {
        yield _serializeRtuRequest(packet.pdu, packet.unitId);
      } else {
        throw const ModbusException(
          'Invalid packet type',
          'ModbusRtuRequestSerializer can only handle RTU packets (without transactionId)',
        );
      }
    }
  }

  /// 序列化RTU请求为字节数组
  List<int> serializeRtuRequest(
    ModbusPDURequest request,
    int unitId,
  ) {
    return _serializeRtuRequest(request, unitId);
  }

  /// 序列化RTU请求为字节数组（内部实现）
  List<int> _serializeRtuRequest(
    ModbusPDURequest request,
    int unitId,
  ) {
    final requestDataLength = _calculateRtuRequestDataLength(request);
    final buffer = Uint8List(
      1 + 1 + requestDataLength + 2,
    ); // unitId + fcode + data + CRC
    final view =
        ByteData.view(buffer.buffer)
          ..setUint8(0, unitId)
          ..setUint8(1, _getRequestFunctionCode(request));

    _fillRequestData(view, request, 2);

    // 添加CRC校验
    final crc = ModbusCrc.calculate(buffer.sublist(0, buffer.length - 2));
    view.setUint16(buffer.length - 2, crc, Endian.little);

    return buffer;
  }

  /// 获取请求的功能码
  int _getRequestFunctionCode(ModbusPDURequest request) {
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

  /// 计算RTU请求数据长度
  int _calculateRtuRequestDataLength(ModbusPDURequest request) {
    return switch (request) {
      ReadCoilsRequest() => 4, // startAddr + quantity
      ReadDiscreteInputsRequest() => 4, // startAddr + quantity
      ReadHoldingRegistersRequest() => 4, // startAddr + quantity
      ReadInputRegistersRequest() => 4, // startAddr + quantity
      WriteSingleCoilRequest() => 4, // addr + value
      WriteSingleRegisterRequest() => 4, // addr + value
      WriteMultipleCoilsRequest() =>
        5 +
            ((request.values.length + 7) ~/
                8), // startAddr + quantity + byteCount + data
      WriteMultipleRegistersRequest() =>
        5 +
            (request.values.length *
                2), // startAddr + quantity + byteCount + data
    };
  }

  /// 填充请求数据
  void _fillRequestData(
    ByteData view,
    ModbusPDURequest request,
    int offset,
  ) {
    switch (request) {
      case ReadCoilsRequest():
        view.setUint16(offset, request.startAddress);
        view.setUint16(offset + 2, request.quantity);
      case ReadDiscreteInputsRequest():
        view.setUint16(offset, request.startAddress);
        view.setUint16(offset + 2, request.quantity);
      case ReadHoldingRegistersRequest():
        view.setUint16(offset, request.startAddress);
        view.setUint16(offset + 2, request.quantity);
      case ReadInputRegistersRequest():
        view.setUint16(offset, request.startAddress);
        view.setUint16(offset + 2, request.quantity);
      case WriteSingleCoilRequest():
        view.setUint16(offset, request.address);
        view.setUint16(offset + 2, request.value ? 0xFF00 : 0x0000);
      case WriteSingleRegisterRequest():
        view.setUint16(offset, request.address);
        view.setUint16(offset + 2, request.value);
      case WriteMultipleCoilsRequest():
        view.setUint16(offset, request.startAddress);
        view.setUint16(offset + 2, request.values.length);
        final byteCount = (request.values.length + 7) ~/ 8;
        view.setUint8(offset + 4, byteCount);
        _packCoilsToBytes(view, request.values, offset + 5);
      case WriteMultipleRegistersRequest():
        view.setUint16(offset, request.startAddress);
        view.setUint16(offset + 2, request.values.length);
        view.setUint8(offset + 4, request.values.length * 2);
        for (var i = 0; i < request.values.length; i++) {
          view.setUint16(offset + 5 + i * 2, request.values[i]);
        }
    }
  }

  /// 将线圈布尔值打包成字节
  void _packCoilsToBytes(ByteData view, List<bool> coils, int offset) {
    final byteCount = (coils.length + 7) ~/ 8;
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
}

/// Modbus RTU响应解析器
/// 将RTU字节流转换为ModbusResponsePacket
class ModbusRtuResponseParser
    extends StreamTransformerBase<Uint8List, ModbusResponsePacket> {
  final _buffer = BytesBuilder();

  @override
  Stream<ModbusResponsePacket> bind(Stream<Uint8List> stream) async* {
    await for (final data in stream) {
      _buffer.add(data);

      // RTU 协议处理
      while (_buffer.length >= 4) {
        // 最小RTU包：unitId + functionCode + 2字节数据
        final bytes = _buffer.toBytes();
        final packetLength = _calculateRtuResponsePacketLength(bytes);

        if (packetLength == null || _buffer.length < packetLength) {
          break;
        }

        final packet = Uint8List.fromList(
          _buffer.takeBytes().sublist(0, packetLength),
        );
        yield _parseRtuResponse(packet);
      }
    }
  }

  /// 解析RTU响应包
  ModbusResponsePacket parseRtuResponse(Uint8List packet) {
    return _parseRtuResponse(packet);
  }

  /// 解析RTU响应包（内部方法）
  ModbusResponsePacket _parseRtuResponse(Uint8List packet) {
    // 验证CRC
    final dataWithoutCrc = packet.sublist(0, packet.length - 2);
    final receivedCrc = ByteData.view(
      packet.buffer,
    ).getUint16(packet.length - 2, Endian.little);
    final calculatedCrc = ModbusCrc.calculate(dataWithoutCrc);

    if (receivedCrc != calculatedCrc) {
      throw ModbusException(
        'CRC check failed',
        'Expected 0x${calculatedCrc.toRadixString(16)}, got 0x${receivedCrc.toRadixString(16)}',
      );
    }

    final unitId = packet[0];
    final functionCodeByte = packet[1];
    final data = packet.sublist(2, packet.length - 2); // 去掉CRC

    final response = _parseResponseData(functionCodeByte, data);

    return ModbusPacket.respone(
          unitId,
          response,
          null, // RTU协议没有transactionId
        )
        as ModbusResponsePacket;
  }

  /// 解析响应数据
  ModbusPDUResponse _parseResponseData(int functionCode, Uint8List data) {
    final dataView = ByteData.view(data.buffer);

    // 处理错误响应
    if (functionCode >= 0x80) {
      return ModbusPDUResponse.error(dataView.getUint8(0));
    }

    return switch (functionCode) {
      0x01 => _parseCoilsResponse(data), // ReadCoils
      0x02 => _parseDiscreteInputsResponse(data), // ReadDiscreteInputs
      0x03 => _parseHoldingRegistersResponse(data), // ReadHoldingRegisters
      0x04 => _parseInputRegistersResponse(data), // ReadInputRegisters
      0x05 => _parseSingleCoilResponse(data), // WriteSingleCoil
      0x06 => _parseSingleRegisterResponse(data), // WriteSingleRegister
      0x0F => _parseMultipleCoilsResponse(data), // WriteMultipleCoils
      0x10 => _parseMultipleRegistersResponse(data), // WriteMultipleRegisters
      _ =>
        throw ModbusException(
          'Unsupported function code',
          'Function code 0x${functionCode.toRadixString(16)} is not supported',
        ),
    };
  }

  /// 解析读取线圈响应
  ModbusPDUResponse _parseCoilsResponse(Uint8List data) {
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

  /// 解析读取离散输入响应
  ModbusPDUResponse _parseDiscreteInputsResponse(Uint8List data) {
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

  /// 解析读取保持寄存器响应
  ModbusPDUResponse _parseHoldingRegistersResponse(Uint8List data) {
    final byteCount = data[0];
    final registerData = data.sublist(1, 1 + byteCount);
    final registers = <int>[];

    for (var i = 0; i < byteCount; i += 2) {
      registers.add(ByteData.view(registerData.buffer).getUint16(i));
    }

    return ModbusPDUResponse.readHoldingRegisters(registers);
  }

  /// 解析读取输入寄存器响应
  ModbusPDUResponse _parseInputRegistersResponse(Uint8List data) {
    final byteCount = data[0];
    final registerData = data.sublist(1, 1 + byteCount);
    final registers = <int>[];

    for (var i = 0; i < byteCount; i += 2) {
      registers.add(ByteData.view(registerData.buffer).getUint16(i));
    }

    return ModbusPDUResponse.readInputRegisters(registers);
  }

  /// 解析写单个线圈响应
  ModbusPDUResponse _parseSingleCoilResponse(Uint8List data) {
    final dataView = ByteData.view(data.buffer);
    final address = dataView.getUint16(0);
    final value = dataView.getUint16(2) == 0xFF00;
    return ModbusPDUResponse.writeSingleCoil(address, value);
  }

  /// 解析写单个寄存器响应
  ModbusPDUResponse _parseSingleRegisterResponse(Uint8List data) {
    final dataView = ByteData.view(data.buffer);
    final address = dataView.getUint16(0);
    final value = dataView.getUint16(2);
    return ModbusPDUResponse.writeSingleRegister(address, value);
  }

  /// 解析写多个线圈响应
  ModbusPDUResponse _parseMultipleCoilsResponse(Uint8List data) {
    final dataView = ByteData.view(data.buffer);
    final startAddress = dataView.getUint16(0);
    final quantity = dataView.getUint16(2);
    return ModbusPDUResponse.writeMultipleCoils(startAddress, quantity);
  }

  /// 解析写多个寄存器响应
  ModbusPDUResponse _parseMultipleRegistersResponse(Uint8List data) {
    final dataView = ByteData.view(data.buffer);
    final startAddress = dataView.getUint16(0);
    final quantity = dataView.getUint16(2);
    return ModbusPDUResponse.writeMultipleRegisters(startAddress, quantity);
  }

  /// 计算RTU响应包长度
  int? _calculateRtuResponsePacketLength(Uint8List bytes) {
    if (bytes.length < 2) return null;

    final functionCode = bytes[1];

    // 处理错误响应
    if (functionCode >= 0x80) {
      return 5; // unitId + errorCode + exceptionCode + CRC
    }

    return switch (functionCode) {
      0x01 => bytes.length >= 3 ? 3 + bytes[2] + 2 : null,
      // ReadCoils: unitId + fcode + byteCount + data + CRC
      0x02 => bytes.length >= 3 ? 3 + bytes[2] + 2 : null,
      // ReadDiscreteInputs: unitId + fcode + byteCount + data + CRC
      0x03 => bytes.length >= 3 ? 3 + bytes[2] + 2 : null,
      // ReadHoldingRegisters: unitId + fcode + byteCount + data + CRC
      0x04 => bytes.length >= 3 ? 3 + bytes[2] + 2 : null,
      // ReadInputRegisters: unitId + fcode + byteCount + data + CRC
      0x05 => 8,
      // WriteSingleCoil: unitId + fcode + addr + value + CRC
      0x06 => 8,
      // WriteSingleRegister: unitId + fcode + addr + value + CRC
      0x0F => 8,
      // WriteMultipleCoils: unitId + fcode + startAddr + quantity + CRC
      0x10 => 8,
      // WriteMultipleRegisters: unitId + fcode + startAddr + quantity + CRC
      _ => null,
    };
  }
}

/// Modbus RTU响应序列化器
/// 将ModbusResponsePacket转换为RTU字节流
class ModbusRtuResponseSerializer
    extends StreamTransformerBase<ModbusResponsePacket, Uint8List> {
  @override
  Stream<Uint8List> bind(Stream<ModbusResponsePacket> stream) async* {
    await for (final packet in stream) {
      // 只处理RTU包（没有transactionId的包）
      if (packet.transactionId == null) {
        yield _serializeRtuResponse(packet.pdu, packet.unitId);
      } else {
        throw const ModbusException(
          'Invalid packet type',
          'ModbusRtuResponseSerializer can only handle RTU packets (without transactionId)',
        );
      }
    }
  }

  /// 序列化RTU响应为字节数组
  Uint8List serializeRtuResponse(
    ModbusPDUResponse response,
    int unitId,
  ) {
    return _serializeRtuResponse(response, unitId);
  }

  /// 序列化RTU响应为字节数组（内部实现）
  Uint8List _serializeRtuResponse(
    ModbusPDUResponse response,
    int unitId,
  ) {
    final dataLength = ModbusPduProcessor.calculateResponseDataLength(response);
    final buffer = Uint8List(
      1 + 1 + dataLength + 2,
    ); // unitId + fcode + data + CRC
    final view =
        ByteData.view(buffer.buffer)
          ..setUint8(0, unitId)
          ..setUint8(1, ModbusPduProcessor.getFunctionCode(response));

    ModbusPduProcessor.fillResponseData(view, response, 2);

    // 添加CRC校验
    final crc = ModbusCrc.calculate(buffer.sublist(0, buffer.length - 2));
    view.setUint16(buffer.length - 2, crc, Endian.little);

    return buffer;
  }
}

/// Modbus CRC计算工具类
class ModbusCrc {
  static const List<int> _crcTable = [
    0x0000,
    0xC0C1,
    0xC181,
    0x0140,
    0xC301,
    0x03C0,
    0x0280,
    0xC241,
    0xC601,
    0x06C0,
    0x0780,
    0xC741,
    0x0500,
    0xC5C1,
    0xC481,
    0x0440,
    0xCC01,
    0x0CC0,
    0x0D80,
    0xCD41,
    0x0F00,
    0xCFC1,
    0xCE81,
    0x0E40,
    0x0A00,
    0xCAC1,
    0xCB81,
    0x0B40,
    0xC901,
    0x09C0,
    0x0880,
    0xC841,
    0xD801,
    0x18C0,
    0x1980,
    0xD941,
    0x1B00,
    0xDBC1,
    0xDA81,
    0x1A40,
    0x1E00,
    0xDEC1,
    0xDF81,
    0x1F40,
    0xDD01,
    0x1DC0,
    0x1C80,
    0xDC41,
    0x1400,
    0xD4C1,
    0xD581,
    0x1540,
    0xD701,
    0x17C0,
    0x1680,
    0xD641,
    0xD201,
    0x12C0,
    0x1380,
    0xD341,
    0x1100,
    0xD1C1,
    0xD081,
    0x1040,
    0xF001,
    0x30C0,
    0x3180,
    0xF141,
    0x3300,
    0xF3C1,
    0xF281,
    0x3240,
    0x3600,
    0xF6C1,
    0xF781,
    0x3740,
    0xF501,
    0x35C0,
    0x3480,
    0xF441,
    0x3C00,
    0xFCC1,
    0xFD81,
    0x3D40,
    0xFF01,
    0x3FC0,
    0x3E80,
    0xFE41,
    0xFA01,
    0x3AC0,
    0x3B80,
    0xFB41,
    0x3900,
    0xF9C1,
    0xF881,
    0x3840,
    0x2800,
    0xE8C1,
    0xE981,
    0x2940,
    0xEB01,
    0x2BC0,
    0x2A80,
    0xEA41,
    0xEE01,
    0x2EC0,
    0x2F80,
    0xEF41,
    0x2D00,
    0xEDC1,
    0xEC81,
    0x2C40,
    0xE401,
    0x24C0,
    0x2580,
    0xE541,
    0x2700,
    0xE7C1,
    0xE681,
    0x2640,
    0x2200,
    0xE2C1,
    0xE381,
    0x2340,
    0xE101,
    0x21C0,
    0x2080,
    0xE041,
    0xA001,
    0x60C0,
    0x6180,
    0xA141,
    0x6300,
    0xA3C1,
    0xA281,
    0x6240,
    0x6600,
    0xA6C1,
    0xA781,
    0x6740,
    0xA501,
    0x65C0,
    0x6480,
    0xA441,
    0x6C00,
    0xACC1,
    0xAD81,
    0x6D40,
    0xAF01,
    0x6FC0,
    0x6E80,
    0xAE41,
    0xAA01,
    0x6AC0,
    0x6B80,
    0xAB41,
    0x6900,
    0xA9C1,
    0xA881,
    0x6840,
    0x7800,
    0xB8C1,
    0xB981,
    0x7940,
    0xBB01,
    0x7BC0,
    0x7A80,
    0xBA41,
    0xBE01,
    0x7EC0,
    0x7F80,
    0xBF41,
    0x7D00,
    0xBDC1,
    0xBC81,
    0x7C40,
    0xB401,
    0x74C0,
    0x7580,
    0xB541,
    0x7700,
    0xB7C1,
    0xB681,
    0x7640,
    0x7200,
    0xB2C1,
    0xB381,
    0x7340,
    0xB101,
    0x71C0,
    0x7080,
    0xB041,
    0x5000,
    0x90C1,
    0x9181,
    0x5140,
    0x9301,
    0x53C0,
    0x5280,
    0x9241,
    0x9601,
    0x56C0,
    0x5780,
    0x9741,
    0x5500,
    0x95C1,
    0x9481,
    0x5440,
    0x9C01,
    0x5CC0,
    0x5D80,
    0x9D41,
    0x5F00,
    0x9FC1,
    0x9E81,
    0x5E40,
    0x5A00,
    0x9AC1,
    0x9B81,
    0x5B40,
    0x9901,
    0x59C0,
    0x5880,
    0x9841,
    0x8801,
    0x48C0,
    0x4980,
    0x8941,
    0x4B00,
    0x8BC1,
    0x8A81,
    0x4A40,
    0x4E00,
    0x8EC1,
    0x8F81,
    0x4F40,
    0x8D01,
    0x4DC0,
    0x4C80,
    0x8C41,
    0x4400,
    0x84C1,
    0x8581,
    0x4540,
    0x8701,
    0x47C0,
    0x4680,
    0x8641,
    0x8201,
    0x42C0,
    0x4380,
    0x8341,
    0x4100,
    0x81C1,
    0x8081,
    0x4040,
  ];

  /// 计算CRC-16/MODBUS校验码
  static int calculate(Uint8List data) {
    var crc = 0xFFFF;
    for (final byte in data) {
      final index = (crc ^ byte) & 0xFF;
      crc = ((crc >> 8) ^ _crcTable[index]) & 0xFFFF;
    }
    return crc;
  }
}
