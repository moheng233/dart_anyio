import 'dart:async';
import 'dart:io';

import 'dart:typed_data';

import 'package:anyio_template/service.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'serial.g.dart';

@JsonEnum(alwaysCreate: true)
enum SerialPartiy { none, odd, even, mark, space }

@immutable
@JsonSerializable()
final class TransportOptionForSerial {
  const TransportOptionForSerial(
    this.dev, {
    this.baudRate = 9600,
    this.dataBits = 8,
    this.stopBits = 1,
    this.parity = SerialPartiy.none,
  });

  factory TransportOptionForSerial.fromJson(Map<dynamic, dynamic> json) =>
      _$TransportOptionForSerialFromJson(json);

  final String dev;
  final int baudRate;
  final int dataBits;
  final int stopBits;
  final SerialPartiy parity;
}

final class TransportForSerialImpl
    implements TransportSessionBase<TransportOptionForSerial> {
  @override
  Future<void> close() {
    // TODO: implement close
    throw UnimplementedError();
  }

  @override
  // TODO: implement isOpened
  bool get isOpened => throw UnimplementedError();

  @override
  Future<void> open() {
    // TODO: implement open
    throw UnimplementedError();
  }

  @override
  // TODO: implement read
  Stream<Uint8List> get read => throw UnimplementedError();

  @override
  // TODO: implement write
  StreamSink<List<int>> get write => throw UnimplementedError();
}
