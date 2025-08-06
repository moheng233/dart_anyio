import 'dart:async';
import 'dart:typed_data';

import 'frame.dart';
import 'transformers/rtu.dart' as rtu;
import 'transformers/tcp.dart' as tcp;

/// Modbus客户端请求转换器
/// 将ModbusRequestPacket转换为字节流发送给服务器
class ModbusClientRequestTransformer
    extends StreamTransformerBase<ModbusRequestPacket, Uint8List> {
  final tcp.ModbusTcpRequestSerializer _tcpSerializer =
      tcp.ModbusTcpRequestSerializer();
  final rtu.ModbusRtuRequestSerializer _rtuSerializer =
      rtu.ModbusRtuRequestSerializer();

  @override
  Stream<Uint8List> bind(Stream<ModbusRequestPacket> stream) async* {
    await for (final packet in stream) {
      if (packet.transactionId != null) {
        // TCP协议（有transactionId）
        await for (final bytes in _tcpSerializer.bind(Stream.value(packet))) {
          yield bytes;
        }
      } else {
        // RTU协议（没有transactionId）
        await for (final bytes in _rtuSerializer.bind(Stream.value(packet))) {
          yield bytes;
        }
      }
    }
  }

  /// 静态方法：序列化单个请求包
  static Uint8List serializeRequest(ModbusRequestPacket packet) {
    if (packet.transactionId != null) {
      // TCP协议（有transactionId）
      final serializer = tcp.ModbusTcpRequestSerializer();
      return serializer.serializeTcpRequest(
        packet.pdu,
        packet.unitId,
        packet.transactionId!,
      );
    } else {
      // RTU协议（没有transactionId）
      final serializer = rtu.ModbusRtuRequestSerializer();
      return serializer.serializeRtuRequest(packet.pdu, packet.unitId);
    }
  }
}

/// Modbus客户端响应转换器
/// 将服务器返回的字节流转换为ModbusResponsePacket
class ModbusClientResponseTransformer
    extends StreamTransformerBase<Uint8List, ModbusResponsePacket> {
  ModbusClientResponseTransformer({this.isRtu = false});

  final bool isRtu;

  @override
  Stream<ModbusResponsePacket> bind(Stream<Uint8List> stream) {
    if (isRtu) {
      return _parseRtuResponses(stream);
    } else {
      return _parseTcpResponses(stream);
    }
  }

  /// 解析TCP响应流
  Stream<ModbusResponsePacket> _parseTcpResponses(
    Stream<Uint8List> stream,
  ) async* {
    final buffer = BytesBuilder();

    await for (final data in stream) {
      buffer.add(data);

      while (buffer.length > 6) {
        final header = buffer.toBytes().sublist(0, 6);
        final length = ByteData.view(header.buffer).getUint16(4) + 6;

        if (buffer.length < length) {
          break;
        }

        final packet = Uint8List.fromList(
          buffer.takeBytes().sublist(0, length),
        );
        yield _parseTcpResponse(packet);
      }
    }
  }

  /// 解析RTU响应流
  Stream<ModbusResponsePacket> _parseRtuResponses(
    Stream<Uint8List> stream,
  ) async* {
    final buffer = BytesBuilder();

    await for (final data in stream) {
      buffer.add(data);

      while (buffer.length >= 4) {
        final bytes = buffer.toBytes();
        final packetLength = _calculateRtuResponseLength(bytes);

        if (packetLength == null || buffer.length < packetLength) {
          break;
        }

        final packet = Uint8List.fromList(
          buffer.takeBytes().sublist(0, packetLength),
        );
        yield _parseRtuResponse(packet);
      }
    }
  }

  /// 解析单个TCP响应包
  ModbusResponsePacket _parseTcpResponse(Uint8List packet) {
    final view = ByteData.view(packet.buffer);
    final transactionId = view.getUint16(0);
    final unitId = packet[6];
    final functionCodeByte = packet[7];
    final data = packet.sublist(8);

    final response = _parseResponseData(functionCodeByte, data);
    return ModbusPacket.respone(unitId, response, transactionId)
        as ModbusResponsePacket;
  }

  /// 解析单个RTU响应包
  ModbusResponsePacket _parseRtuResponse(Uint8List packet) {
    // 验证CRC
    final dataWithoutCrc = packet.sublist(0, packet.length - 2);
    final receivedCrc = ByteData.view(
      packet.buffer,
    ).getUint16(packet.length - 2, Endian.little);
    final calculatedCrc = rtu.ModbusCrc.calculate(dataWithoutCrc);

    if (receivedCrc != calculatedCrc) {
      throw ModbusException(
        'CRC check failed',
        'Expected 0x${calculatedCrc.toRadixString(16)}, got 0x${receivedCrc.toRadixString(16)}',
      );
    }

    final unitId = packet[0];
    final functionCodeByte = packet[1];
    final data = packet.sublist(2, packet.length - 2);

    final response = _parseResponseData(functionCodeByte, data);
    return ModbusPacket.respone(unitId, response, null) as ModbusResponsePacket;
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

  /// 解析线圈读取响应
  ModbusPDUResponse _parseCoilsResponse(Uint8List data) {
    final byteCount = data[0];
    final values = <bool>[];

    for (var byteIndex = 0; byteIndex < byteCount; byteIndex++) {
      final byte = data[1 + byteIndex];
      for (var bitIndex = 0; bitIndex < 8; bitIndex++) {
        values.add((byte & (1 << bitIndex)) != 0);
      }
    }

    return ModbusPDUResponse.readCoils(values);
  }

  /// 解析离散输入读取响应
  ModbusPDUResponse _parseDiscreteInputsResponse(Uint8List data) {
    final byteCount = data[0];
    final values = <bool>[];

    for (var byteIndex = 0; byteIndex < byteCount; byteIndex++) {
      final byte = data[1 + byteIndex];
      for (var bitIndex = 0; bitIndex < 8; bitIndex++) {
        values.add((byte & (1 << bitIndex)) != 0);
      }
    }

    return ModbusPDUResponse.readDiscreteInputs(values);
  }

  /// 解析保持寄存器读取响应
  ModbusPDUResponse _parseHoldingRegistersResponse(Uint8List data) {
    final byteCount = data[0];
    final values = <int>[];
    final dataView = ByteData.view(data.buffer);

    for (var i = 0; i < byteCount ~/ 2; i++) {
      values.add(dataView.getUint16(1 + i * 2));
    }

    return ModbusPDUResponse.readHoldingRegisters(values);
  }

  /// 解析输入寄存器读取响应
  ModbusPDUResponse _parseInputRegistersResponse(Uint8List data) {
    final byteCount = data[0];
    final values = <int>[];
    final dataView = ByteData.view(data.buffer);

    for (var i = 0; i < byteCount ~/ 2; i++) {
      values.add(dataView.getUint16(1 + i * 2));
    }

    return ModbusPDUResponse.readInputRegisters(values);
  }

  /// 解析单个线圈写入响应
  ModbusPDUResponse _parseSingleCoilResponse(Uint8List data) {
    final dataView = ByteData.view(data.buffer);
    final address = dataView.getUint16(0);
    final value = dataView.getUint16(2) == 0xFF00;

    return ModbusPDUResponse.writeSingleCoil(address, value);
  }

  /// 解析单个寄存器写入响应
  ModbusPDUResponse _parseSingleRegisterResponse(Uint8List data) {
    final dataView = ByteData.view(data.buffer);
    final address = dataView.getUint16(0);
    final value = dataView.getUint16(2);

    return ModbusPDUResponse.writeSingleRegister(address, value);
  }

  /// 解析多个线圈写入响应
  ModbusPDUResponse _parseMultipleCoilsResponse(Uint8List data) {
    final dataView = ByteData.view(data.buffer);
    final startAddress = dataView.getUint16(0);
    final quantity = dataView.getUint16(2);

    return ModbusPDUResponse.writeMultipleCoils(startAddress, quantity);
  }

  /// 解析多个寄存器写入响应
  ModbusPDUResponse _parseMultipleRegistersResponse(Uint8List data) {
    final dataView = ByteData.view(data.buffer);
    final startAddress = dataView.getUint16(0);
    final quantity = dataView.getUint16(2);

    return ModbusPDUResponse.writeMultipleRegisters(startAddress, quantity);
  }

  /// 计算RTU响应长度
  int? _calculateRtuResponseLength(Uint8List bytes) {
    if (bytes.length < 2) return null;

    final functionCode = bytes[1];

    // 错误响应
    if (functionCode >= 0x80) {
      return 5; // unitId + errorCode + errorType + CRC
    }

    return switch (functionCode) {
      0x01 =>
        bytes.length >= 3
            ? 3 + bytes[2] + 2
            : null, // ReadCoils: header + byteCount + data + CRC
      0x02 => bytes.length >= 3 ? 3 + bytes[2] + 2 : null, // ReadDiscreteInputs
      0x03 =>
        bytes.length >= 3 ? 3 + bytes[2] + 2 : null, // ReadHoldingRegisters
      0x04 => bytes.length >= 3 ? 3 + bytes[2] + 2 : null, // ReadInputRegisters
      0x05 => 8, // WriteSingleCoil: unitId + functionCode + addr + value + CRC
      0x06 =>
        8, // WriteSingleRegister: unitId + functionCode + addr + value + CRC
      0x0F =>
        8, // WriteMultipleCoils: unitId + functionCode + startAddr + quantity + CRC
      0x10 =>
        8, // WriteMultipleRegisters: unitId + functionCode + startAddr + quantity + CRC
      _ => null,
    };
  }
}

/// Modbus客户端工具类
/// 提供完整的客户端功能，包括请求发送和响应接收
class ModbusClient {
  ModbusClient({this.isRtu = false});

  final bool isRtu;

  /// 创建请求转换器
  ModbusClientRequestTransformer get requestTransformer =>
      ModbusClientRequestTransformer();

  /// 创建响应转换器
  ModbusClientResponseTransformer get responseTransformer =>
      ModbusClientResponseTransformer(isRtu: isRtu);

  /// 序列化请求包为字节数组
  Uint8List serializeRequest(ModbusRequestPacket packet) {
    return ModbusClientRequestTransformer.serializeRequest(packet);
  }

  /// 创建TCP请求包
  static ModbusRequestPacket createTcpRequest(
    int unitId,
    ModbusPDURequest pdu,
    int transactionId,
  ) {
    return ModbusPacket.request(unitId, pdu, transactionId)
        as ModbusRequestPacket;
  }

  /// 创建RTU请求包
  static ModbusRequestPacket createRtuRequest(
    int unitId,
    ModbusPDURequest pdu,
  ) {
    return ModbusPacket.request(unitId, pdu, null) as ModbusRequestPacket;
  }
}
