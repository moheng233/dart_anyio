import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:anyio_template/service.dart';
import 'package:dart_mappable/dart_mappable.dart';

import 'action_manager.dart';
import 'variable_manager.dart';

final class ChannelManagerImpl {
  ChannelManagerImpl({
    required this.deviceAdapter,
    required this.adapterIsolate,
    required this.adapterC2S,
    required this.adapterS2C,
    required HashMap<String, HashMap<String, VariableInfo>> variableDefinitions,
    required HashMap<String, HashMap<String, ActionInfo>> actionDefinitions,
  }) {
    for (final entry in adapterC2S.entries) {
      final adapterId = entry.key;
      final recv = entry.value;
      final ready = _ready.putIfAbsent(adapterId, Completer<void>.new);

      // We store the subscription for later cancellation in dispose();
      // ignore: cancel_subscriptions
      final sub = recv.listen((event) {
        if (event is ChannelReadyEvent) {
          adapterS2C[adapterId] = event.portForS2C;
          if (!ready.isCompleted) ready.complete();
          return;
        }
        if (event is ChannelDeviceStatusEvent) {
          // 更新设备在线状态，并继续向上游转发
          _deviceOnline[event.deviceId] = event.online;
          _aggReadCtrl.add(event);
          return;
        }
        if (event is ChannelBaseEvent) {
          _aggReadCtrl.add(event);
        }
      });

      _c2sSubs[adapterId] = sub;
    }

    variables = VariableManager(definitions: variableDefinitions);
    actions = ActionManager(_routeWrite, definitions: actionDefinitions);

    // 附加聚合读流到变量/动作管理器
    variables.attach(_aggReadCtrl.stream);
    actions.attach(_aggReadCtrl.stream);
  }

  static final _factories = <String, ChannelFactoryHandler>{};
  static final _channelOptionMap = <Type, String>{};
  final Map<String, bool> _deviceOnline = {};
  static final _templateOptionMap = <Type, String>{};

  final HashMap<String, String> deviceAdapter;
  final HashMap<String, Isolate> adapterIsolate;
  final HashMap<String, ReceivePort> adapterC2S;
  final HashMap<String, SendPort> adapterS2C;

  // 聚合 read
  final _aggReadCtrl = StreamController<ChannelBaseEvent>.broadcast();

  // 适配器握手完成事件与订阅句柄

  // 设备在线状态查询（null 表示未知/尚未上报）
  bool getDeviceOnline(String deviceId) => _deviceOnline[deviceId] ?? false;
  Map<String, bool> getAllDeviceOnline() => {
    for (final id in deviceIds) id: _deviceOnline[id] ?? false,
  };
  final Map<String, Completer<void>> _ready = {};
  final Map<String, StreamSubscription<dynamic>> _c2sSubs = {};

  // 变量/动作管理器
  late final VariableManager variables;
  late final ActionManager actions;

  // 统一写入接口（动作调用）
  Future<bool> invokeAction(String deviceId, String actionId, Object? value) {
    return actions.invoke(deviceId, actionId, value);
  }

  // Wrap to keep generic constraint and readability
  Stream<E> listenEvent<E extends ChannelBaseEvent>() =>
      _aggReadCtrl.stream.where(_isType<E>).cast<E>();

  static bool _isType<T>(Object e) => e is T;

  Stream<Object?> listenValue(String deviceId, String tagId) =>
      variables.listenValue(deviceId, tagId);

  // 统一读取接口（变量）
  Object? readValue(String deviceId, String tagId) =>
      variables.readValue(deviceId, tagId);

  Map<String, Object?> readAllValues(String deviceId) =>
      variables.readAllValues(deviceId);

  Iterable<String> get deviceIds => deviceAdapter.keys;

  // ------- 定义查询（便于上层访问） -------
  Map<String, VariableInfo> getVariableDefinitions(String deviceId) =>
      variables.getVariableDefinitions(deviceId);

  VariableInfo? getVariableInfo(String deviceId, String tagId) =>
      variables.getVariableInfo(deviceId, tagId);

  Map<String, ActionInfo> getActionDefinitions(String deviceId) =>
      actions.getActionDefinitions(deviceId);

  ActionInfo? getActionInfo(String deviceId, String actionId) =>
      actions.getActionInfo(deviceId, actionId);

  /// 等待指定适配器完成握手
  Future<void> waitAdapterReady(String adapterId) {
    return (_ready[adapterId] ??= Completer<void>()).future;
  }

  /// 资源释放：取消端口订阅并关闭聚合流
  Future<void> dispose() async {
    for (final sub in _c2sSubs.values) {
      await sub.cancel();
    }
    _c2sSubs.clear();
    await _aggReadCtrl.close();
  }

  /// 等待所有适配器完成握手
  Future<void> waitAllAdaptersReady() async {
    for (final adapterId in adapterC2S.keys) {
      await waitAdapterReady(adapterId);
    }
  }

  void _routeWrite(DeviceBaseEvent event) {
    String? deviceId;

    if (event is DeviceActionInvokeEvent) {
      deviceId = event.deviceId;
    }

    if (deviceId == null) return;
    final port = adapterS2C[deviceAdapter[deviceId]];
    if (port == null) {
      throw StateError('未找到设备所属适配器: $deviceId');
    }

    port.send(event);
  }

  static Future<ChannelManagerImpl> initialize(
    ServiceOption service,
    Map<String, TemplateOption> templates, {
    Logger? logger,
  }) async {
    final devices = service.devices;

    final deviceForAdapter = <String, String>{};
    final devicesByAdapter = <String, List<ChannelOptionGroup>>{};
    // 预构建各设备的变量/动作定义
    final variableDefinitions =
        HashMap<String, HashMap<String, VariableInfo>>();
    final actionDefinitions = HashMap<String, HashMap<String, ActionInfo>>();

    logger?.info('Load device count for ${devices.length}');

    for (final device in devices) {
      final template = templates[device.template];

      final channelOptionForAdapterId =
          _channelOptionMap[device.channel.runtimeType];
      final templateOptionForAdpaterId = template == null
          ? null
          : _templateOptionMap[template.template.runtimeType];

      if (channelOptionForAdapterId != templateOptionForAdpaterId) {
        // TODO(me): 处理模板和通道设置使用的适配器不一致的问题
      }

      final adapterId = channelOptionForAdapterId!;

      deviceForAdapter[device.name] = adapterId;
      devicesByAdapter.putIfAbsent(adapterId, () => []).add((
        deviceId: device.name,
        template: template!.template,
        channel: device.channel,
      ));

      // 记录定义
      variableDefinitions[device.name] = HashMap<String, VariableInfo>.from(
        template.points,
      );
      actionDefinitions[device.name] = HashMap<String, ActionInfo>();
    }

    final adapterIsolate = <String, Isolate>{};
    final adapterC2S = <String, ReceivePort>{};
    final adapterS2C = <String, SendPort>{};

    for (final element in devicesByAdapter.entries) {
      final adapterHandler = _factories[element.key]!;

      final c2sPort = ReceivePort('Adapter[${element.key}]S2C');

      adapterC2S[element.key] = c2sPort;

      logger?.info('Spawn [${element.key}] Adapter Isolate Begin');

      final isolate = await Isolate.spawn(
        (message) => adapterHandler(message.$1, message.$2),
        (element.value, c2sPort.sendPort),
        debugName: element.key,
      );

      adapterIsolate[element.key] = isolate;

      logger?.info('Spawn [${element.key}] Adapter Isolate End');

      // 订阅与握手处理已在 ChannelManagerImpl 内部完成，这里不再重复订阅。
    }

    final mgr = ChannelManagerImpl(
      deviceAdapter: HashMap.from(deviceForAdapter),
      adapterIsolate: HashMap.from(adapterIsolate),
      adapterC2S: HashMap.from(adapterC2S),
      adapterS2C: HashMap.from(adapterS2C),
      variableDefinitions: variableDefinitions,
      actionDefinitions: actionDefinitions,
    );

    // 等待所有适配器握手完成，保持与旧逻辑一致的时序
    logger?.info('Waiting adapters ready ...');
    await mgr.waitAllAdaptersReady();
    logger?.info('All adapters ready');

    return mgr;
  }

  static void
  registerFactory<CP extends ChannelOptionBase, TP extends ChannelTemplateBase>(
    String adapterId,
    ChannelFactoryHandler handler, {
    required ClassMapperBase<CP> channelOptionMapper,
    required ClassMapperBase<TP> templateOptionMapper,
  }) {
    _factories[adapterId] = handler;
    _channelOptionMap[CP] = adapterId;
    _templateOptionMap[TP] = adapterId;
  }
}
