import 'dart:typed_data';

import 'package:anyio_template/service.dart';

import 'template.dart';

bool asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final v = value.toLowerCase().trim();
    if (v == 'true' || v == '1' || v == 'on') return true;
    if (v == 'false' || v == '0' || v == 'off') return false;
  }
  throw FormatException('Unsupported bool value: $value');
}

int toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.parse(value);
  throw FormatException('Unsupported int value: $value');
}

num toNum(Object? value) {
  if (value is num) return value;
  if (value is String) return num.parse(value);
  throw FormatException('Unsupported num value: $value');
}

List<int> bytesToRegisters(Uint8List bytes) {
  assert(bytes.length.isEven, 'Modbus registers come in 2-byte pairs');
  final regs = <int>[];
  for (var i = 0; i < bytes.length; i += 2) {
    regs.add(((bytes[i] & 0xFF) << 8) | (bytes[i + 1] & 0xFF));
  }
  return regs;
}

List<int> encodeFloat(ModbusPoint point, Object? value) {
  final numVal = toNum(value).toDouble();
  final endian = point.endian.endian;
  final swap = point.endian.swap;

  if (point.length == 4) {
    // double (8 bytes)
    final d = ByteData(8)..setFloat64(0, numVal, endian);
    final bytes = Uint8List.view(d.buffer);
    return bytesToRegisters(bytes);
  }

  // float32 (4 bytes), with optional swap
  final bytes = Uint8List(4);
  if (!swap) {
    final d = ByteData(4)..setFloat32(0, numVal, endian);
    final t = Uint8List.view(d.buffer);
    bytes.setAll(0, [t[0], t[1], t[2], t[3]]);
  } else {
    // Build big-endian bytes then rearrange per swap rules
    final d = ByteData(4)..setFloat32(0, numVal);
    final t = Uint8List.view(d.buffer);
    if (endian == Endian.big) {
      // BADC
      bytes.setAll(0, [t[1], t[0], t[3], t[2]]);
    } else {
      // CDAB
      bytes.setAll(0, [t[2], t[3], t[0], t[1]]);
    }
  }
  return bytesToRegisters(bytes);
}

List<int> encodeInt(
  ModbusPoint point,
  Object? value, {
  required bool signed,
}) {
  final intVal = toInt(value);
  final endian = point.endian.endian;
  final swap = point.endian.swap;
  final regs = <int>[];

  if (point.length == 1) {
    final data = ByteData(2);
    if (signed) {
      data.setInt16(0, intVal, endian);
    } else {
      data.setUint16(0, intVal, endian);
    }
    final b = Uint8List.view(data.buffer);
    regs.add((b[0] << 8) | b[1]);
    return regs;
  }

  if (point.length == 2) {
    // 32-bit
    final bytes = Uint8List(4);
    if (!swap) {
      final d = ByteData(4);
      if (signed) {
        d.setInt32(0, intVal, endian);
      } else {
        d.setUint32(0, intVal, endian);
      }
      final t = Uint8List.view(d.buffer);
      bytes.setAll(0, [t[0], t[1], t[2], t[3]]);
    } else {
      // Build big-endian bytes of value, then rearrange per swap rules
      final d = ByteData(4)..setUint32(0, intVal);
      final t = Uint8List.view(d.buffer);
      if (endian == Endian.big) {
        // BADC -> [t1,t0,t3,t2]
        bytes.setAll(0, [t[1], t[0], t[3], t[2]]);
      } else {
        // CDAB -> [t2,t3,t0,t1]
        bytes.setAll(0, [t[2], t[3], t[0], t[1]]);
      }
    }
    return bytesToRegisters(bytes);
  }

  if (point.length == 4) {
    // 64-bit
    final d = ByteData(8);
    if (signed) {
      d.setInt64(0, intVal, endian);
    } else {
      d.setUint64(0, intVal, endian);
    }
    final bytes = Uint8List.view(d.buffer);
    return bytesToRegisters(bytes);
  }

  // Unsupported length
  throw UnsupportedError('Unsupported int length: ${point.length}');
}

List<int> encodeToRegisters(ModbusPoint point, Object? value) {
  try {
    switch (point.type) {
  case VariableType.bool:
        final v = asBool(value) ? 1 : 0;
        return [v & 0xFFFF];
  case VariableType.int:
        return encodeInt(point, value, signed: true);
  case VariableType.uint:
        return encodeInt(point, value, signed: false);
  case VariableType.float:
        return encodeFloat(point, value);
    }
  } on Exception {
    return const <int>[];
  }
}
