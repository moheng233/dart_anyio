import 'dart:io';

import 'dart:typed_data';

import 'package:anyio_template/service.dart';

final class TransportForSerialImpl extends TransportForSerial {
  TransportForSerialImpl(super.option);

  @override
  Future<void> close() {
    // TODO: implement close
    throw UnimplementedError();
  }

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
  IOSink get write => throw UnimplementedError();
}
