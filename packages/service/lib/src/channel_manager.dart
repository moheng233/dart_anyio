import 'dart:collection';

import 'package:anyio_template/service.dart';

import 'isolated_channel.dart';

final class ChannelManagerImpl extends ChannelManager {
  ChannelManagerImpl({this.useIsolatedChannels = true});

  /// Whether to run channels in separate isolates
  final bool useIsolatedChannels;

  final factorys = <ChannelFactory>{};

  final channelOptionMap = <Type, ChannelFactory>{};
  final templateOptionMap = <Type, ChannelFactory>{};
  final sessionMap = <Type, ChannelFactory>{};

  final sessions = HashMap<String, ChannelSession>();
  final isolatedSessions = HashMap<String, IsolatedChannelSession>();

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
    
    ChannelSession session;
    
    if (useIsolatedChannels) {
      // Create isolated channel session
      final isolatedSession = IsolatedChannelSession(
        deviceId: deviceId,
        channelFactory: factory,
        channelOption: channelOption,
        templateOption: templateOption,
        transport: transport,
        deviceEvent: deviceEvent,
      );
      
      isolatedSessions[deviceId] = isolatedSession;
      session = isolatedSession;
    } else {
      // Create regular channel session
      session = factory.create(
        deviceId,
        deviceEvent: deviceEvent,
        transport: transport,
        channelOption: channelOption,
        templateOption: templateOption,
      );
    }
    
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

  /// Get isolated channel session for restart operations
  IsolatedChannelSession? getIsolatedSession(String deviceId) {
    return isolatedSessions[deviceId];
  }

  /// Restart an isolated channel
  Future<void> restartChannel(String deviceId) async {
    final isolatedSession = isolatedSessions[deviceId];
    if (isolatedSession != null) {
      await isolatedSession.restart();
    }
  }

  /// Stop and cleanup all channels
  Future<void> stopAll() async {
    // Stop all isolated channels
    for (final session in isolatedSessions.values) {
      await session.dispose();
    }
    
    // Stop regular channels
    for (final session in sessions.values) {
      if (session is! IsolatedChannelSession) {
        session.stop();
      }
    }
    
    sessions.clear();
    isolatedSessions.clear();
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
