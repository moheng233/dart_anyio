import 'dart:io';

import 'package:anyio_template/service.dart';

import 'transports/tcp.dart';

final class TransportManagerImpl extends TransportManager {
  final transports = <TransportOption, TransportSessionBase>{};

  @override
  TransportSessionBase getOrCreate(TransportOption option) {
    var transport = transports[option];

    if (transport == null) {
      transport = switch (option) {
        TransportOptionForSerial() => throw UnimplementedError(),
        TransportOptionForTcp() => TransportForTcpImpl(option),
        TransportOptionForCan() => throw UnimplementedError(),
      };

      transports[option] = transport;
    }

    return transport;
  }

  @override
  TransportSessionBase? getTry(TransportOption option) {
    return transports[option];
  }
}
