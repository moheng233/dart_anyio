import 'dart:async';
import 'dart:typed_data';

import './frame.dart';

class ModbusRequestTransformer
    extends StreamTransformerBase<Uint8List, ModbusFrameRequest> {
  final _buffer = BytesBuilder();

  @override
  Stream<ModbusFrameRequest> bind(Stream<Uint8List> stream) async* {
    await for (final data in stream) {
      _buffer.add(data);
      while (_buffer.length > 6) {
        final header = _buffer.toBytes().sublist(0, 6);
        final length = ByteData.view(header.buffer).getUint16(4) + 6;

        if (_buffer.length < length) {
          break;
        }

        final packet = Uint8List.fromList(
          _buffer.takeBytes().sublist(0, length),
        );
        yield parseRequest(packet);
      }
    }
  }

  static ModbusFrameRequest parseRequest(Uint8List packet) {
    final view = ByteData.view(packet.buffer);
    final transactionId = view.getUint16(0);
    final unitId = packet[6];
    final functionCodeByte = packet[7];

    {
      final data = packet.sublist(8);
      final view = ByteData.view(data.buffer);

      return switch (functionCodeByte) {
        0x03 => ModbusFrameRequest.readHoldingRegisters(
          transactionId,
          unitId,
          view.getUint16(0),
          view.getUint16(2),
        ),
        0x06 => ModbusFrameRequest.writeSingleRegister(
          transactionId,
          unitId,
          view.getUint16(0),
          view.getUint16(2),
        ),
        _ => throw Exception('Unsupported function code'),
      };
    }
  }
}

class ModbusResponseTransformer
    extends StreamTransformerBase<ModbusFrameResponse, Uint8List> {
  @override
  Stream<Uint8List> bind(Stream<ModbusFrameResponse> stream) async* {
    await for (final data in stream) {
      yield serializeResponse(data);
    }
  }

  static Uint8List serializeResponse(ModbusFrameResponse response) {
    final dataLength = _calculateDataLength(response);
    final buffer = Uint8List(6 + dataLength); // Header + unitId + fcode + data
    final view =
        ByteData.view(buffer.buffer)
          // MBAP Header
          ..setUint16(0, response.transactionId)
          ..setUint16(4, dataLength) // Length field
          // PDU
          ..setUint8(6, response.unitId)
          ..setUint8(7, switch (response) {
            ReadHoldingRegistersResponse() => 0x03,
            WriteSingleRegisterResponse() => 0x06,

            ModbusErrorResponse() => 0x00,
          });

    switch (response) {
      case ReadHoldingRegistersResponse():
        view.setUint8(8, response.values.length * 2);

        for (var i = 0; i < response.values.length; i++) {
          view.setUint16(9 + i * 2, response.values[i]);
        }
      case WriteSingleRegisterResponse():
        view.setUint16(8, response.address);
        view.setUint16(10, response.value);
      default:
    }

    return buffer;
  }

  static int _calculateDataLength(ModbusFrameResponse response) {
    return switch (response) {
      ReadHoldingRegistersResponse() => 2 + 1 + (response.values.length * 2),
      WriteSingleRegisterResponse() => 2 + 4,
      ModbusErrorResponse() => 2 + 1,
    };
  }
}

class Uint8ListToIntListTransformer
    extends StreamTransformerBase<Uint8List, List<int>> {
  @override
  Stream<List<int>> bind(Stream<Uint8List> stream) async* {
    await for (final raw in stream) {
      yield raw.toList();
    }
  }
}
