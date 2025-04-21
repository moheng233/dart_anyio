import 'dart:async';
import 'dart:typed_data';

import 'package:anyio_modbus_slave/modbus_slave.dart';
import 'package:test/test.dart';

import 'test_cases.dart';

void main() {
  group('Modbus frame', () {
    test('splie test', () async {
      for (final cases in resquesTestCasesList) {
        final controller = StreamController<Uint8List>();

        final output = controller.stream.transform(ModbusRequestTransformer());

        controller
          ..add(Uint8List.fromList(cases.raw.sublist(0, 7)))
          ..add(Uint8List.fromList(cases.raw.sublist(7)));

        final frame = await output.first;

        expect(frame, cases.frame);

        await controller.close();
      }
    });
  });
}
