import 'package:dart_mappable/dart_mappable.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'event.dart';
import 'logger.dart';
import 'template.dart';
import 'transport.dart';

abstract base class ChannelManager {
  /// 注册 [channelType] 对应的 [ChannelFactory]
  void registerFactory(String channelType, ChannelFactory channel);

  /// 根据 [channelType] 获取对应的 [ChannelFactory]
  ChannelFactory getFactory(String channelType);

  /// 根据 [deviceId] 获取可以使用的 [ChannelSession]
  ChannelSession getSession(String deviceId);

  ChannelSession create(
    String deviceId,
    String channelType, {
    required Stream<DeviceBaseEvent> deviceEvent,
    required TransportSession transport,
    required dynamic channelOption,
    required dynamic templateOption,
  });

  dynamic loadChannelOption(String channelType, Map<dynamic, dynamic> json);
  dynamic loadTemplateOption(String channelType, Map<dynamic, dynamic> json);
}

typedef ChannelSession =
    ChannelSessionBase<ChannelOptionBase, ChannelTemplateBase>;

abstract base class ChannelSessionBase<
  CP extends ChannelOptionBase,
  TP extends ChannelTemplateBase
> {
  ChannelSessionBase({required this.write});

  Stream<ChannelBaseEvent> get read;

  @protected
  final Stream<DeviceBaseEvent> write;

  void open();
  void stop();
}

typedef ChannelFactory =
    ChannelFactoryBase<
      ChannelOptionBase,
      ChannelTemplateBase,
      ChannelSessionBase<ChannelOptionBase, ChannelTemplateBase>
    >;

/// 通道适配器工厂
abstract base class ChannelFactoryBase<
  CP extends ChannelOptionBase,
  TP extends ChannelTemplateBase,
  S extends ChannelSessionBase<CP, TP>
> {
  ClassMapperBase<CP> get channelOptionMapper;
  ClassMapperBase<TP> get templateOptionMapper;

  S create(
    String deviceId, {
    required Stream<DeviceBaseEvent> deviceEvent,
    required TransportSession transport,
    required CP channelOption,
    required TP templateOption,
  });
}

/// 适配器插件基类
abstract base class AdapterPluginBase {
  String get name;
  String get version;

  Future<void> up(ChannelManager manager, Logger logger);
  Future<void> down(ChannelManager manager);
}
