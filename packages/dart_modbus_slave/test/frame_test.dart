import 'dart:typed_data';

import 'package:anyio_modbus_slave/modbus_slave.dart';
import 'package:test/test.dart';

import 'test_cases.dart';

void main() {
  group('Modbus Request Test', () {
    setUp(() {
      // Additional setup goes here.
    });

    test('ReadHoldingRegisters', () {
      for (final cases in resquesTestCasesList) {
        final data = ModbusRequestTransformer.parseRequest(
          Uint8List.fromList(cases.raw),
        );

        expect(data, cases.frame);
      }
    });
  });

  group('Modbus Response Test', () {
    setUp(() {
      // Additional setup goes here.
    });

    test('ReadHoldingRegisters', () {
      for (final cases in responseTestCasesList) {
        final data = ModbusResponseTransformer.serializeResponse(cases.frame);

        expect(data, Uint16List.fromList(cases.raw));
      }
    });
  });
}
