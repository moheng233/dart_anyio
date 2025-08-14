import 'dart:collection';

import 'package:anyio_template/service.dart';

final class ChannelManagerImpl extends ChannelManager {
  final factorys = HashMap<String, ChannelFactory>();
  final sessions = HashMap<String, ChannelSession>();

  @override
  ChannelSession create(
    String deviceId,
    String channelType, {
    required Stream<DeviceBaseEvent> deviceEvent,
    required TransportSession transport,
    required dynamic channelOption,
    required dynamic templateOption,
  }) {
    if (channelType.isEmpty) {
      throw ArgumentError('channelType 不能为空');
    }
    final existed = sessions[deviceId];
    if (existed != null) {
      return existed;
    }
    final factory = getFactory(channelType);
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
  ChannelFactory getFactory(String channelType) {
    final factory = factorys[channelType];
    if (factory == null) {
      throw StateError('未注册的通道类型: $channelType');
    }
    return factory;
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
  dynamic loadChannelOption(String channelType, Map<dynamic, dynamic> json) {
    return getFactory(channelType).loadChannelOption(json);
  }

  @override
  dynamic loadTemplateOption(String channelType, Map<dynamic, dynamic> json) {
    return getFactory(channelType).loadTemplateOption(json);
  }

  @override
  void registerFactory(String channelType, ChannelFactory channel) {
    if (factorys.containsKey(channelType)) {
      throw StateError('通道类型已注册: $channelType');
    }
    factorys[channelType] = channel;
  }
}
