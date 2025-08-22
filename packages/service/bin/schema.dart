import 'package:anyio_service/src/channel_manager.dart';
import 'package:anyio_service/src/transport_manager.dart';
import 'package:anyio_service/src/transports/tcp.dart';
import 'package:anyio_template/service.dart';
import 'package:dart_mappable_schema/json_schema.dart';

import 'package:anyio_adapter_modbus/adapter.dart';

void main(List<String> args) {
  final channels = ChannelManagerImpl()
    ..registerFactory(ChannelFactoryForModbus());
  final transports = TransportManagerImpl()
    ..register(TransportFactoryForTcpImpl());

  print(ServiceOptionMapper.ensureInitialized().toJsonSchema().toJson());
}
