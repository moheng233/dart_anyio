import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'generated_bindings.dart' as vci;

extension ArrayCharExtensions on Array<Char> {
  String toDartString() {
    final bytesBuilder = BytesBuilder();
    var index = 0;
    while (this[index] != 0) {
      bytesBuilder.addByte(this[index]);
      ++index;
    }

    final bytes = bytesBuilder.takeBytes();
    return utf8.decode(bytes);
  }
}

/// 包装 BoardInfo 结构体
class BoardInfo {
  BoardInfo.fromPointer(vci.BoardInfo ptr)
    : hwVersion = ptr.hw_Version,
      fwVersion = ptr.fw_Version,
      drVersion = ptr.dr_Version,
      inVersion = ptr.in_Version,
      irqNum = ptr.irq_Num,
      canNum = ptr.can_Num,
      serialNum = ptr.str_Serial_Num.toDartString(),
      hwType = ptr.str_hw_Type.toDartString(),
      reserved = List.generate(4, (i) => ptr.Reserved[i]);
  final int hwVersion;
  final int fwVersion;
  final int drVersion;
  final int inVersion;
  final int irqNum;
  final int canNum;
  final String serialNum;
  final String hwType;
  final List<int> reserved;
}

/// 包装 CanObj 结构体
class CanObj {
  CanObj.fromPointer(vci.CanObj ptr)
    : id = ptr.ID,
      timeStamp = ptr.TimeStamp,
      timeFlag = ptr.TimeFlag,
      sendType = ptr.SendType,
      remoteFlag = ptr.RemoteFlag,
      externFlag = ptr.ExternFlag,
      dataLen = ptr.DataLen,
      data = List.generate(8, (i) => ptr.Data[i]),
      reserved = List.generate(3, (i) => ptr.Reserved[i]);
  final int id;
  final int timeStamp;
  final int timeFlag;
  final int sendType;
  final int remoteFlag;
  final int externFlag;
  final int dataLen;
  final List<int> data;
  final List<int> reserved;
}

/// CAN 设备包装类
class CanDevice {
  CanDevice(this.deviceType, this.deviceInd);
  final int deviceType;
  final int deviceInd;

  // 静态函数
  static int openDevice(int deviceType, int deviceInd, int reserved) {
    return vci.openDevice(deviceType, deviceInd, reserved);
  }

  static int closeDevice(int deviceType, int deviceInd) {
    return vci.closeDevice(deviceType, deviceInd);
  }

  static int findUsbDevice2() {
    final ptr = calloc<vci.BoardInfo>();
    final result = vci.findUsbDevice2(ptr);
    calloc.free(ptr);
    return result;
  }

  static int usbDeviceReset(int devType, int devIndex, int reserved) {
    return vci.usbDeviceReset(devType, devIndex, reserved);
  }

  // 实例方法
  int initCAN(
    int canInd, {
    required int accCode,
    required int accMask,
    required int reserved,
    required int filter,
    required int timing0,
    required int timing1,
    required int mode,
  }) {
    final ptr = calloc<vci.InitConfig>();
    ptr.ref.AccCode = accCode;
    ptr.ref.AccMask = accMask;
    ptr.ref.Reserved = reserved;
    ptr.ref.Filter = filter;
    ptr.ref.Timing0 = timing0;
    ptr.ref.Timing1 = timing1;
    ptr.ref.Mode = mode;

    final result = vci.initCAN(deviceType, deviceInd, canInd, ptr);

    calloc.free(ptr);
    return result;
  }

  BoardInfo? readBoardInfo() {
    final ptr = calloc<vci.BoardInfo>();
    final result = vci.readBoardInfo(deviceType, deviceInd, ptr);
    BoardInfo? info;
    if (result == 1) {
      info = BoardInfo.fromPointer(ptr.ref);
    }
    calloc.free(ptr);
    return info;
  }

  int setReference(int canInd, int refType, Pointer<Void> pData) {
    return vci.setReference(deviceType, deviceInd, canInd, refType, pData);
  }

  int getReceiveNum(int canInd) {
    return vci.getReceiveNum(deviceType, deviceInd, canInd);
  }

  int clearBuffer(int canInd) {
    return vci.clearBuffer(deviceType, deviceInd, canInd);
  }

  int startCAN(int canInd) {
    return vci.startCAN(deviceType, deviceInd, canInd);
  }

  int resetCAN(int canInd) {
    return vci.resetCAN(deviceType, deviceInd, canInd);
  }

  int transmit(int canInd, List<CanObj> objs) {
    final len = objs.length;
    final ptr = calloc<vci.CanObj>(len);
    for (var i = 0; i < len; i++) {
      ptr[i].ID = objs[i].id;
      ptr[i].TimeStamp = objs[i].timeStamp;
      ptr[i].TimeFlag = objs[i].timeFlag;
      ptr[i].SendType = objs[i].sendType;
      ptr[i].RemoteFlag = objs[i].remoteFlag;
      ptr[i].ExternFlag = objs[i].externFlag;
      ptr[i].DataLen = objs[i].dataLen;
      for (var j = 0; j < 8; j++) {
        ptr[i].Data[j] = objs[i].data[j];
      }
      for (var j = 0; j < 3; j++) {
        ptr[i].Reserved[j] = objs[i].reserved[j];
      }
    }
    final result = vci.transmit(deviceType, deviceInd, canInd, ptr, len);
    calloc.free(ptr);
    return result;
  }

  List<CanObj> receive(int canInd, int len, int waitTime) {
    final ptr = calloc<vci.CanObj>(len);
    final result = vci.receive(
      deviceType,
      deviceInd,
      canInd,
      ptr,
      len,
      waitTime,
    );
    final objs = <CanObj>[];
    for (var i = 0; i < result; i++) {
      objs.add(CanObj.fromPointer(ptr[i]));
    }
    calloc.free(ptr);
    return objs;
  }
}
