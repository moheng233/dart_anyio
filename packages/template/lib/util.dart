import 'dart:typed_data';

final class ValueListHelper {
  static bool? readBool(List<dynamic> temp) {
    if (temp[0] is bool) {
      return temp[0] as bool;
    } else if (temp[0] is int) {
      return temp[0] != 0;
    }

    return null;
  }

  static ByteData viewTemp(List<dynamic> temp) {
    return ByteData.view(
      Uint16List.fromList(temp.cast<int>()).buffer,
    );
  }

  static int? readInt(List<dynamic> temp, int length, Endian endian) {
    final view = viewTemp(temp);

    switch (length) {
      case 1:
        return view.getInt8(0);
      case 2:
        return view.getInt16(0, endian);
      case 4:
        return view.getInt32(0, endian);
      case 8:
        return view.getInt64(0, endian);
    }

    return null;
  }

  static double? readFloat(List<dynamic> temp, int length, Endian endian) {
    final view = viewTemp(temp);

    switch (length) {
      case 4:
        return view.getFloat32(0, endian);
      case 8:
        return view.getFloat64(0, endian);
    }

    return null;
  }

  static int? readUint(List<dynamic> temp, int length, Endian endian) {
    final view = viewTemp(temp);

    switch (length) {
      case 1:
        return view.getUint8(0);
      case 2:
        return view.getUint16(0, endian);
      case 4:
        return view.getUint32(0, endian);
      case 8:
        return view.getUint64(0, endian);
    }

    return null;
  }
}
