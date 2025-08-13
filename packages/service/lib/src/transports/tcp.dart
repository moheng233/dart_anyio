import 'dart:io';
import 'dart:typed_data';

import 'package:anyio_template/service.dart';

final class TransportForTcpImpl extends TransportForTcp {
  TransportForTcpImpl(super.option);

  Socket? socket;

  @override
  bool get isOpened => socket != null;

  @override
  Stream<Uint8List> get read => socket!;

  @override
  IOSink get write => socket!;

  @override
  Future<void> close() async {
    await socket?.close();
    socket = null;
  }

  @override
  Future<void> open() async {
    socket = await Socket.connect(
      InternetAddress(
        option.host,
        type: InternetAddressType.IPv4,
      ),
      option.port,
    );
  }
}
