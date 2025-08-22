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
    return ModbusPduProcessor.getRequestFunctionCode(request);
  }

  /// 计算TCP请求数据长度
  int _calculateTcpRequestDataLength(ModbusPDURequest request) {
    // 2 bytes: unitId + functionCode + body length
    return 2 + ModbusPduProcessor.calculateRequestBodyLength(request);
  }

  /// 填充请求数据
  void _fillRequestData(
    ByteData view,
    ModbusPDURequest request,
    int offset,
  ) {
    ModbusPduProcessor.fillRequestData(view, request, offset);
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
    return ModbusPduProcessor.parseResponse(functionCode, data);
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
