import 'dart:isolate';

import 'package:anyio_template/service.dart';
import 'package:anyio_template/src/logger.dart';

import 'src/protocol.dart';

export 'src/protocol.dart';

final class AdapterPluginForModbus extends AdapterPluginBase {
  @override
  String get name => 'Modbus';
  @override
  String get version => '1.0.0';

  @override
  Future<void> up(ChannelManager manager, Logger logger) async {
    manager.registerFactory(ChannelFactoryForModbus());
  }

  @override
  Future<void> down(ChannelManager manager) async {}
}
