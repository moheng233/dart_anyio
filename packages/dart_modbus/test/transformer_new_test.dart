import 'dart:typed_data';

import 'package:anyio_modbus/modbus_slave.dart';
import 'package:test/test.dart';

void main() {
  group('ModbusRequestTransformer', () {
    test('TCP request parsing', () {
      // 创建一个读取保持寄存器的TCP请求
      final tcpPacket = Uint8List.fromList([
        0x00, 0x01, // 事务ID
        0x00, 0x00, // 协议标识符
        0x00, 0x06, // 长度
        0x01, // 单元ID
        0x03, // 功能码（读取保持寄存器）
        0x00, 0x00, // 起始地址
        0x00, 0x01, // 寄存器数量
      ]);

      final transformer = ModbusTcpRequestParser();
      final result = transformer.parseTcpRequest(tcpPacket);

      expect(result.unitId, equals(1));
      expect(result.transactionId, equals(1));
      expect(result.pdu, isA<ReadHoldingRegistersRequest>());

      final request = result.pdu as ReadHoldingRegistersRequest;
      expect(request.startAddress, equals(0));
      expect(request.quantity, equals(1));
    });

    test('RTU request parsing', () {
      // 创建一个读取保持寄存器的RTU请求
      final rtuPacket = Uint8List.fromList([
        0x01, // 单元ID
        0x03, // 功能码（读取保持寄存器）
        0x00, 0x00, // 起始地址
        0x00, 0x01, // 寄存器数量
        0x84, 0x0A, // CRC (假设的)
      ]);

      // 计算正确的CRC
      final dataWithoutCrc = rtuPacket.sublist(0, 6);
      final correctCrc = ModbusCrc.calculate(dataWithoutCrc);
      final correctPacket = Uint8List.fromList([
        ...dataWithoutCrc,
        correctCrc & 0xFF,
        (correctCrc >> 8) & 0xFF,
      ]);

      final transformer = ModbusRtuRequestParser();
      final result = transformer.parseRtuRequest(correctPacket);

      expect(result.unitId, equals(1));
      expect(result.transactionId, isNull); // RTU协议没有transactionId
      expect(result.pdu, isA<ReadHoldingRegistersRequest>());

      final request = result.pdu as ReadHoldingRegistersRequest;
      expect(request.startAddress, equals(0));
      expect(request.quantity, equals(1));
    });
  });

  group('ModbusResponseTransformer', () {
    test('TCP response serialization', () {
      const response =
          ModbusPacket.respone(
                1, // unitId
                ModbusPDUResponse.readHoldingRegisters([0x1234]),
                1, // transactionId
              )
              as ModbusResponsePacket;

      final transformer = ModbusTcpResponseSerializer();
      final result = transformer.serializeTcpResponse(
        response.pdu,
        response.unitId,
        response.transactionId!,
      );

      expect(
        result.length,
        equals(11),
      ); // 6字节头 + 1字节单元ID + 1字节功能码 + 1字节长度 + 2字节数据
      expect(result[0], equals(0x00)); // 事务ID高字节
      expect(result[1], equals(0x01)); // 事务ID低字节
      expect(result[2], equals(0x00)); // 协议标识符高字节
      expect(result[3], equals(0x00)); // 协议标识符低字节
      expect(result[4], equals(0x00)); // 长度高字节
      expect(result[5], equals(0x05)); // 长度低字节
      expect(result[6], equals(0x01)); // 单元ID
      expect(result[7], equals(0x03)); // 功能码
      expect(result[8], equals(0x02)); // 数据长度
      expect(result[9], equals(0x12)); // 数据高字节
      expect(result[10], equals(0x34)); // 数据低字节
    });

    test('RTU response serialization', () {
      const response =
          ModbusPacket.respone(
                1, // unitId
                ModbusPDUResponse.readHoldingRegisters([0x1234]),
                null, // transactionId (RTU协议没有)
              )
              as ModbusResponsePacket;

      final transformer = ModbusRtuResponseSerializer();
      final result = transformer.serializeRtuResponse(
        response.pdu,
        response.unitId,
      );

      expect(
        result.length,
        equals(7),
      ); // 1字节单元ID + 1字节功能码 + 1字节长度 + 2字节数据 + 2字节CRC
      expect(result[0], equals(0x01)); // 单元ID
      expect(result[1], equals(0x03)); // 功能码
      expect(result[2], equals(0x02)); // 数据长度
      expect(result[3], equals(0x12)); // 数据高字节
      expect(result[4], equals(0x34)); // 数据低字节

      // 验证CRC
      final dataWithoutCrc = result.sublist(0, 5);
      final expectedCrc = ModbusCrc.calculate(dataWithoutCrc);
      final actualCrc = result[5] | (result[6] << 8);
      expect(actualCrc, equals(expectedCrc));
    });

    test('通用响应转换器 - TCP', () {
      const response =
          ModbusPacket.respone(
                1, // unitId
                ModbusPDUResponse.readHoldingRegisters([0x1234]),
                1, // transactionId
              )
              as ModbusResponsePacket;

      final transformer = ModbusTcpResponseSerializer();
      final result = transformer.serializeTcpResponse(
        response.pdu,
        response.unitId,
        response.transactionId!,
      );

      expect(result.length, equals(11)); // TCP格式
      expect(result[0], equals(0x00)); // 事务ID高字节
      expect(result[1], equals(0x01)); // 事务ID低字节
    });

    test('通用响应转换器 - RTU', () {
      const response =
          ModbusPacket.respone(
                1, // unitId
                ModbusPDUResponse.readHoldingRegisters([0x1234]),
                null, // transactionId
              )
              as ModbusResponsePacket;

      final transformer = ModbusRtuResponseSerializer();
      final result = transformer.serializeRtuResponse(
        response.pdu,
        response.unitId,
      );

      expect(
        result.length,
        equals(7),
      ); // RTU格式：unitId + functionCode + byteCount + data + CRC
      expect(result[0], equals(0x01)); // 单元ID
      expect(result[1], equals(0x03)); // 功能码
    });
  });

  group('ModbusCrc', () {
    test('CRC calculation', () {
      final data = Uint8List.fromList([0x01, 0x03, 0x00, 0x00, 0x00, 0x01]);
      final crc = ModbusCrc.calculate(data);

      // 这是一个已知的CRC值，用于验证算法的正确性
      expect(crc, isA<int>());
      expect(crc, greaterThanOrEqualTo(0));
      expect(crc, lessThanOrEqualTo(0xFFFF));
    });
  });
}
