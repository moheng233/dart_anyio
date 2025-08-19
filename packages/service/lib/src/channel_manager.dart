import 'dart:collection';

import 'package:anyio_template/service.dart';

final class ChannelManagerImpl extends ChannelManager {
  final factorys = <ChannelFactory>{};

  final channelOptionMap = <Type, ChannelFactory>{};
  final templateOptionMap = <Type, ChannelFactory>{};
  final sessionMap = <Type, ChannelFactory>{};

  final sessions = HashMap<String, ChannelSession>();

  @override
  ChannelSession create(
    String deviceId, {
    required Stream<DeviceBaseEvent> deviceEvent,
    required TransportSession transport,
    required ChannelOptionBase channelOption,
    required ChannelTemplateBase templateOption,
  }) {
    final existed = sessions[deviceId];
    if (existed != null) {
      return existed;
    }
    final factory = channelOptionMap[channelOption.runtimeType]!;
    final session = factory.create(
      deviceId,
      deviceEvent: deviceEvent,
      transport: transport,
      channelOption: channelOption,
      templateOption: templateOption,
    );
    sessions[deviceId] = session;
    return session;
  }

  @override
  ChannelFactory getFactory(Type channelType) {
    return sessionMap[channelType]!;
  }

  @override
  ChannelSession getSession(String deviceId) {
    final session = sessions[deviceId];
    if (session == null) {
      throw StateError('会话不存在: $deviceId');
    }
    return session;
  }

  @override
  void registerFactory<
    CP extends ChannelOptionBase,
    TP extends ChannelTemplateBase,
    S extends ChannelSessionBase<CP, TP>
  >(ChannelFactoryBase<CP, TP, S> factory) {
    if (factorys.contains(factory)) {
      throw StateError('通道类型已注册: $factory');
    }

    factorys.add(factory);
    channelOptionMap[CP] = factory;
    templateOptionMap[TP] = factory;
    sessionMap[S] = factory;

    // 访问一下, 使其Mapper生效
    factory
      ..channelOptionMapper
      ..templateOptionMapper;
  }
}
