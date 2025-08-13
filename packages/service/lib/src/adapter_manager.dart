import 'package:anyio_template/service.dart';

final class AdapterManagerImpl extends ChannelManager {
  AdapterManagerImpl();

  final adapterFactorys = <AdapterPluginBase>[];
  final adapterInstances = <AdapterInstance>[];

  @override
  void register(AdapterPluginBase factory) {

  }
}
