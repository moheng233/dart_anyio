import 'dart:typed_data';

extension ByteDataHelper on ByteData {
  /// 获取32位有符号整数，支持 Modbus 字节序
  /// 对于32位数据，Modbus定义了4种字节序：
  /// - ABCD: 标准大端序
  /// - DCBA: 标准小端序
  /// - BADC: 字内字节交换的大端序
  /// - CDAB: 字内字节交换的小端序
  int getInt32Swap(
    int byteOffset, {
    Endian endian = Endian.big,
    bool swap = false,
  }) {
    final result = getUint32Swap(byteOffset, endian: endian, swap: swap);
    return (result & 0x80000000) != 0 ? result - 0x100000000 : result;
  }

  /// 获取32位无符号整数，支持 Modbus 字节序
  int getUint32Swap(
    int byteOffset, {
    Endian endian = Endian.big,
    bool swap = false,
  }) {
    if (!swap) {
      // 标准字节序：ABCD (大端) 或 DCBA (小端)
      return getUint32(byteOffset, endian);
    }

    // 字节交换：BADC 或 CDAB
    // 交换每个16位字内的字节顺序
    final byte0 = getUint8(byteOffset);
    final byte1 = getUint8(byteOffset + 1);
    final byte2 = getUint8(byteOffset + 2);
    final byte3 = getUint8(byteOffset + 3);

    if (endian == Endian.big) {
      // BADC: [B,A,D,C] = [byte1,byte0,byte3,byte2]
      return (byte1 << 24) | (byte0 << 16) | (byte3 << 8) | byte2;
    } else {
      // CDAB: [C,D,A,B] = [byte2,byte3,byte0,byte1]
      return (byte2 << 24) | (byte3 << 16) | (byte0 << 8) | byte1;
    }
  }

  /// 获取32位浮点数，支持 Modbus 字节序
  double getFloat32Swap(
    int byteOffset, {
    Endian endian = Endian.big,
    bool swap = false,
  }) {
    if (!swap) {
      return getFloat32(byteOffset, endian);
    }

    // 使用字节交换逻辑重新排列字节
    final byte0 = getUint8(byteOffset);
    final byte1 = getUint8(byteOffset + 1);
    final byte2 = getUint8(byteOffset + 2);
    final byte3 = getUint8(byteOffset + 3);

    final swappedBytes = Uint8List(4);
    if (endian == Endian.big) {
      // BADC: [B,A,D,C]
      swappedBytes[0] = byte1;
      swappedBytes[1] = byte0;
      swappedBytes[2] = byte3;
      swappedBytes[3] = byte2;
    } else {
      // CDAB: [C,D,A,B]
      swappedBytes[0] = byte2;
      swappedBytes[1] = byte3;
      swappedBytes[2] = byte0;
      swappedBytes[3] = byte1;
    }

    return ByteData.view(swappedBytes.buffer).getFloat32(0);
  }
}
