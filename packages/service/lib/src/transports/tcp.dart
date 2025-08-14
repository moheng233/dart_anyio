import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:anyio_template/service.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'tcp.g.dart';

@immutable
@JsonSerializable()
final class TransportOptionForTcp {
  const TransportOptionForTcp(this.host, this.port);

  factory TransportOptionForTcp.fromJson(Map<dynamic, dynamic> json) =>
      _$TransportOptionForTcpFromJson(json);

  final String host;
  final int port;
}

final class TransportFactoryForTcpImpl
    implements TransportFactoryBase<TransportOptionForTcp> {
  @override
  TransportSessionBase<TransportOptionForTcp> create(
    TransportOptionForTcp option,
  ) {
    return TransportForTcpImpl(option);
  }

  @override
  TransportOptionForTcp loadOption(Map<dynamic, dynamic> json) {
    return TransportOptionForTcp.fromJson(json);
  }

  @override
  String getSessionId(TransportOptionForTcp option) {
    return 'tcp:${option.host}:${option.port}';
  }
}

final class TransportForTcpImpl
    implements TransportSessionBase<TransportOptionForTcp> {
  TransportForTcpImpl(this.option);

  final TransportOptionForTcp option;

  Socket? socket;

  @override
  bool get isOpened => socket != null;

  final readController = StreamController<Uint8List>(sync: true);
  final writeController = StreamController<List<int>>(sync: true);

  @override
  Stream<Uint8List> get read => readController.stream;

  @override
  StreamSink<List<int>> get write => writeController;

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

    unawaited(socket!.pipe(readController));
    unawaited(writeController.stream.pipe(socket!));
  }
}
