import 'dart:async';
import 'dart:typed_data';

import '../frame.dart';
import '../pdu_processor.dart';

/// Modbus TCP请求解析器
/// 将TCP字节流转换为ModbusRequestPacket
class ModbusTcpRequestParser
    extends StreamTransformerBase<Uint8List, ModbusRequestPacket> {
  final _buffer = BytesBuilder();

  @override
  Stream<ModbusRequestPacket> bind(Stream<Uint8List> stream) async* {
    await for (final data in stream) {
      _buffer.add(data);

      // TCP 协议处理
      while (_buffer.length > 6) {
        final header = _buffer.toBytes().sublist(0, 6);
        final length = ByteData.view(header.buffer).getUint16(4) + 6;

        if (_buffer.length < length) {
          break;
        }

        final packet = Uint8List.fromList(
          _buffer.takeBytes().sublist(0, length),
        );
        yield _parseTcpRequest(packet);
      }
    }
  }

  /// 解析TCP请求包
  ModbusRequestPacket parseTcpRequest(Uint8List packet) {
    return _parseTcpRequest(packet);
  }

  /// 解析TCP请求包（内部实现）
  ModbusRequestPacket _parseTcpRequest(Uint8List packet) {
    final view = ByteData.view(packet.buffer);
    final transactionId = view.getUint16(0);
    final unitId = packet[6];
    final functionCodeByte = packet[7];

    final data = packet.sublist(8);

    final request = ModbusPduProcessor.parseRequest(functionCodeByte, data);

    return ModbusPacket.request(
          unitId,
          request,
          transactionId,
        )
        as ModbusRequestPacket;
  }
}

/// Modbus TCP请求序列化器
/// 将ModbusRequestPacket转换为TCP字节流
class ModbusTcpRequestSerializer
    extends StreamTransformerBase<ModbusRequestPacket, List<int>> {
  @override
  Stream<List<int>> bind(Stream<ModbusRequestPacket> stream) async* {
    await for (final packet in stream) {
      // 只处理TCP包（有transactionId的包）
      if (packet.transactionId != null) {
        yield _serializeTcpRequest(
          packet.pdu,
          packet.unitId,
          packet.transactionId!,
        );
      } else {
        throw const ModbusException(
          'Invalid packet type',
          'ModbusTcpRequestSerializer can only handle TCP packets (with transactionId)',
        );
      }
    }
  }

  /// 序列化TCP请求为字节数组
  Uint8List serializeTcpRequest(
    ModbusPDURequest request,
    int unitId,
    int transactionId,
  ) {
    return _serializeTcpRequest(request, unitId, transactionId);
  }

  /// 序列化TCP请求为字节数组（内部实现）
  Uint8List _serializeTcpRequest(
    ModbusPDURequest request,
    int unitId,
    int transactionId,
  ) {
    final requestDataLength = _calculateTcpRequestDataLength(request);
    final buffer = Uint8List(
      6 + requestDataLength,
    ); // Header + unitId + fcode + data
    final view = ByteData.view(buffer.buffer)
      // MBAP Header
      ..setUint16(0, transactionId)
      ..setUint16(2, 0) // Protocol identifier
      ..setUint16(4, requestDataLength) // Length field
      // PDU
      ..setUint8(6, unitId)
      ..setUint8(7, _getRequestFunctionCode(request));

    _fillRequestData(view, request, 8);
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

  /// 计算TCP请求数据长度
  int _calculateTcpRequestDataLength(ModbusPDURequest request) {
    return switch (request) {
      ReadCoilsRequest() => 2 + 4,
      // unitId + fcode + startAddr + quantity
      ReadDiscreteInputsRequest() => 2 + 4,
      // unitId + fcode + startAddr + quantity
      ReadHoldingRegistersRequest() => 2 + 4,
      // unitId + fcode + startAddr + quantity
      ReadInputRegistersRequest() => 2 + 4,
      // unitId + fcode + startAddr + quantity
      WriteSingleCoilRequest() => 2 + 4,
      // unitId + fcode + addr + value
      WriteSingleRegisterRequest() => 2 + 4,
      // unitId + fcode + addr + value
      WriteMultipleCoilsRequest() => 2 + 5 + ((request.values.length + 7) ~/ 8),
      // unitId + fcode + startAddr + quantity + byteCount + data
      WriteMultipleRegistersRequest() => 2 + 5 + (request.values.length * 2),
      // unitId + fcode + startAddr + quantity + byteCount + data
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

/// Modbus TCP响应解析器
/// 将TCP字节流转换为ModbusResponsePacket
class ModbusTcpResponseParser
    extends StreamTransformerBase<Uint8List, ModbusResponsePacket> {
  final _buffer = BytesBuilder();

  @override
  Stream<ModbusResponsePacket> bind(Stream<Uint8List> stream) async* {
    await for (final data in stream) {
      _buffer.add(data);

      // TCP 协议处理
      while (_buffer.length > 6) {
        final header = _buffer.toBytes().sublist(0, 6);
        final length = ByteData.view(header.buffer).getUint16(4) + 6;

        if (_buffer.length < length) {
          break;
        }

        final packet = Uint8List.fromList(
          _buffer.takeBytes().sublist(0, length),
        );
        yield _parseTcpResponse(packet);
      }
    }
  }

  /// 解析TCP响应包
  ModbusResponsePacket parseTcpResponse(Uint8List packet) {
    return _parseTcpResponse(packet);
  }

  /// 解析TCP响应包（内部方法）
  ModbusResponsePacket _parseTcpResponse(Uint8List packet) {
    final view = ByteData.view(packet.buffer);
    final transactionId = view.getUint16(0);
    final unitId = packet[6];
    final functionCodeByte = packet[7];

    final data = packet.sublist(8);

    final response = _parseResponseData(functionCodeByte, data);

    return ModbusPacket.respone(
          unitId,
          response,
          transactionId,
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
      _ => throw ModbusException(
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
}

/// Modbus TCP响应序列化器
/// 将ModbusResponsePacket转换为TCP字节流
class ModbusTcpResponseSerializer
    extends StreamTransformerBase<ModbusResponsePacket, List<int>> {
  @override
  Stream<Uint8List> bind(Stream<ModbusResponsePacket> stream) async* {
    await for (final packet in stream) {
      // 只处理TCP包（有transactionId的包）
      if (packet.transactionId != null) {
        yield _serializeTcpResponse(
          packet.pdu,
          packet.unitId,
          packet.transactionId!,
        );
      } else {
        throw const ModbusException(
          'Invalid packet type',
          'ModbusTcpResponseSerializer can only handle TCP packets (with transactionId)',
        );
      }
    }
  }

  /// 序列化TCP响应为字节数组
  Uint8List serializeTcpResponse(
    ModbusPDUResponse response,
    int unitId,
    int transactionId,
  ) {
    return _serializeTcpResponse(response, unitId, transactionId);
  }

  /// 序列化TCP响应为字节数组（内部实现）
  Uint8List _serializeTcpResponse(
    ModbusPDUResponse response,
    int unitId,
    int transactionId,
  ) {
    final dataLength =
        ModbusPduProcessor.calculateResponseDataLength(response) +
        2; // +2 for unitId and functionCode
    final buffer = Uint8List(6 + dataLength); // Header + unitId + fcode + data
    final view = ByteData.view(buffer.buffer)
      // MBAP Header
      ..setUint16(0, transactionId)
      ..setUint16(2, 0) // Protocol identifier
      ..setUint16(4, dataLength) // Length field
      // PDU
      ..setUint8(6, unitId)
      ..setUint8(7, ModbusPduProcessor.getFunctionCode(response));

    ModbusPduProcessor.fillResponseData(view, response, 8);
    return buffer;
  }
}
