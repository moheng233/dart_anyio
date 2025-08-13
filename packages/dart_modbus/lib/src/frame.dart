// ignore_for_file: avoid_positional_boolean_parameters 统一字段名称需要

import 'package:freezed_annotation/freezed_annotation.dart';

part 'frame.freezed.dart';

/// Modbus异常类
class ModbusException implements Exception {
  const ModbusException(this.message, [this.details]);

  final String message;
  final String? details;

  @override
  String toString() => details != null
      ? 'ModbusException: $message ($details)'
      : 'ModbusException: $message';
}

@Freezed(genericArgumentFactories: true)
sealed class ModbusPacket with _$ModbusPacket {
  const factory ModbusPacket.request(
    int unitId,
    ModbusPDURequest pdu,
    [int? transactionId]
  ) = ModbusRequestPacket;

  const factory ModbusPacket.respone(
    int unitId,
    ModbusPDUResponse pdu,
    [int? transactionId]
  ) = ModbusResponsePacket;
}

@freezed
sealed class ModbusPDURequest with _$ModbusPDURequest {
  // 0x01 - Read Coils
  const factory ModbusPDURequest.readCoils(
    int startAddress,
    int quantity,
  ) = ReadCoilsRequest;

  // 0x02 - Read Discrete Inputs
  const factory ModbusPDURequest.readDiscreteInputs(
    int startAddress,
    int quantity,
  ) = ReadDiscreteInputsRequest;

  // 0x03 - Read Holding Registers
  const factory ModbusPDURequest.readHoldingRegisters(
    int startAddress,
    int quantity,
  ) = ReadHoldingRegistersRequest;

  // 0x04 - Read Input Registers
  const factory ModbusPDURequest.readInputRegisters(
    int startAddress,
    int quantity,
  ) = ReadInputRegistersRequest;

  // 0x05 - Write Single Coil
  const factory ModbusPDURequest.writeSingleCoil(
    int address,
    bool value,
  ) = WriteSingleCoilRequest;

  // 0x06 - Write Single Register
  const factory ModbusPDURequest.writeSingleRegister(
    int address,
    int value,
  ) = WriteSingleRegisterRequest;

  // 0x0F - Write Multiple Coils
  const factory ModbusPDURequest.writeMultipleCoils(
    int startAddress,
    List<bool> values,
  ) = WriteMultipleCoilsRequest;

  // 0x10 - Write Multiple Registers
  const factory ModbusPDURequest.writeMultipleRegisters(
    int startAddress,
    List<int> values,
  ) = WriteMultipleRegistersRequest;
}

@freezed
sealed class ModbusPDUResponse with _$ModbusPDUResponse {
  // 0x01 - Read Coils Response
  const factory ModbusPDUResponse.readCoils(
    List<bool> values,
  ) = ReadCoilsResponse;

  // 0x02 - Read Discrete Inputs Response
  const factory ModbusPDUResponse.readDiscreteInputs(
    List<bool> values,
  ) = ReadDiscreteInputsResponse;

  // 0x03 - Read Holding Registers Response
  const factory ModbusPDUResponse.readHoldingRegisters(
    List<int> values,
  ) = ReadHoldingRegistersResponse;

  // 0x04 - Read Input Registers Response
  const factory ModbusPDUResponse.readInputRegisters(
    List<int> values,
  ) = ReadInputRegistersResponse;

  // 0x05 - Write Single Coil Response
  const factory ModbusPDUResponse.writeSingleCoil(
    int address,
    bool value,
  ) = WriteSingleCoilResponse;

  // 0x06 - Write Single Register Response
  const factory ModbusPDUResponse.writeSingleRegister(
    int address,
    int value,
  ) = WriteSingleRegisterResponse;

  // 0x0F - Write Multiple Coils Response
  const factory ModbusPDUResponse.writeMultipleCoils(
    int startAddress,
    int quantity,
  ) = WriteMultipleCoilsResponse;

  // 0x10 - Write Multiple Registers Response
  const factory ModbusPDUResponse.writeMultipleRegisters(
    int startAddress,
    int quantity,
  ) = WriteMultipleRegistersResponse;

  // 0x80+ - Error Response
  const factory ModbusPDUResponse.error(
    int errorCode,
  ) = ModbusErrorResponse;
}

extension ReadCoilsRequestExtension on ReadCoilsRequest {
  ReadCoilsResponse response(List<bool> values) {
    return ReadCoilsResponse(values);
  }
}

extension ReadDiscreteInputsRequestExtension on ReadDiscreteInputsRequest {
  ReadDiscreteInputsResponse response(List<bool> values) {
    return ReadDiscreteInputsResponse(values);
  }
}

extension ReadHoldingRegistersRequestExtension on ReadHoldingRegistersRequest {
  ReadHoldingRegistersResponse response(List<int> values) {
    return ReadHoldingRegistersResponse(values);
  }
}

extension ReadInputRegistersRequestExtension on ReadInputRegistersRequest {
  ReadInputRegistersResponse response(List<int> values) {
    return ReadInputRegistersResponse(values);
  }
}

extension WriteSingleCoilRequestExtension on WriteSingleCoilRequest {
  WriteSingleCoilResponse response() {
    return WriteSingleCoilResponse(address, value);
  }
}

extension WriteSingleRegisterRequestExtension on WriteSingleRegisterRequest {
  WriteSingleRegisterResponse response() {
    return WriteSingleRegisterResponse(address, value);
  }
}

extension WriteMultipleCoilsRequestExtension on WriteMultipleCoilsRequest {
  WriteMultipleCoilsResponse response() {
    return WriteMultipleCoilsResponse(startAddress, values.length);
  }
}

extension WriteMultipleRegistersRequestExtension
    on WriteMultipleRegistersRequest {
  WriteMultipleRegistersResponse response() {
    return WriteMultipleRegistersResponse(startAddress, values.length);
  }
}
