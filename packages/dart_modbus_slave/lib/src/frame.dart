import 'package:freezed_annotation/freezed_annotation.dart';

part 'frame.freezed.dart';

@freezed
sealed class ModbusFrameRequest with _$ModbusFrameRequest {
  const factory ModbusFrameRequest.readHoldingRegisters(
    int transactionId,
    int unitId,
    int startAddress,
    int quantity,
  ) = ReadHoldingRegistersRequest;

  const factory ModbusFrameRequest.writeSingleRegister(
    int transactionId,
    int unitId,
    int address,
    int value,
  ) = WriteSingleRegisterRequest;
}

@freezed
sealed class ModbusFrameResponse with _$ModbusFrameResponse {
  const factory ModbusFrameResponse.readHoldingRegisters(
    int transactionId,
    int unitId,
    List<int> values,
  ) = ReadHoldingRegistersResponse;
  const factory ModbusFrameResponse.writeSingleRegister(
    int transactionId,
    int unitId,
    int address,
    int value,
  ) = WriteSingleRegisterResponse;

  const factory ModbusFrameResponse.error(
    int transactionId,
    int unitId,
    int errorCode,
  ) = ModbusErrorResponse;
}

extension ReadHoldingRegistersRequestExtension on ReadHoldingRegistersRequest {
  ReadHoldingRegistersResponse response(List<int> values) {
    return ReadHoldingRegistersResponse(transactionId, unitId, values);
  }
}

extension WriteSingleRegisterRequestExtension on WriteSingleRegisterRequest {
  WriteSingleRegisterResponse response() {
    return WriteSingleRegisterResponse(transactionId, unitId, address, value);
  }
}
