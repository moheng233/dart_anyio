import 'dart:async';
import 'dart:collection';

import 'package:anyio_template/service.dart';

/// 变量读管理器：维护所有 deviceId/tagId 的当前值与订阅。
final class VariableManager {
  VariableManager({
    required HashMap<String, HashMap<String, VariableInfo>> definitions,
  }) : _definitions = definitions;

  final _values = HashMap<String, HashMap<String, Object?>>();
  // 变量定义（来自模板）：deviceId -> (tagId -> VariableInfo)
  final HashMap<String, HashMap<String, VariableInfo>> _definitions;
  final _controllers =
      HashMap<String, HashMap<String, StreamController<Object?>>>();
  StreamSubscription<ChannelBaseEvent>? _sub;

  void attach(Stream<ChannelBaseEvent> read) {
    _sub?.cancel();
    _sub = read.listen(_onEvent);
  }

  void _onEvent(ChannelBaseEvent event) {
    if (event is ChannelUpdateEvent) {
      final dev = event.deviceId;
      final devMap = _values.putIfAbsent(dev, HashMap.new);
      final ctrlMap = _controllers.putIfAbsent(dev, HashMap.new);
      for (final v in event.updates) {
        if (v.deviceId != dev) continue;
        final old = devMap[v.tagId];
        if (old != v.value) {
          devMap[v.tagId] = v.value;
          final c = ctrlMap[v.tagId];
          if (c != null && !c.isClosed) c.add(v.value);
        }
      }
    }
  }

  Object? readValue(String deviceId, String tagId) {
    return _values[deviceId]?[tagId];
  }

  Map<String, Object?> readAllValues(String deviceId) {
    final dev = _values[deviceId];
    if (dev == null) return const {};
    return Map<String, Object?>.from(dev);
  }

  // ------------ 定义管理 ------------
  /// 设置某设备的变量定义（覆盖式）。
  void setVariableDefinitions(
    String deviceId,
    Map<String, VariableInfo> definitions,
  ) {
    _definitions[deviceId] = HashMap.of(definitions);
  }

  /// 读取某设备的全部变量定义。
  Map<String, VariableInfo> getVariableDefinitions(String deviceId) {
    final defs = _definitions[deviceId];
    if (defs == null) return const {};
    return Map<String, VariableInfo>.from(defs);
  }

  /// 读取单个变量定义。
  VariableInfo? getVariableInfo(String deviceId, String tagId) {
    return _definitions[deviceId]?[tagId];
  }

  Stream<Object?> listenValue(String deviceId, String tagId) {
    final ctrlMap = _controllers.putIfAbsent(deviceId, HashMap.new);
    var ctrl = ctrlMap[tagId];
    if (ctrl == null) {
      ctrl = StreamController<Object?>.broadcast();
      ctrlMap[tagId] = ctrl;
    }
    return ctrl.stream;
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    for (final map in _controllers.values) {
      for (final c in map.values) {
        await c.close();
      }
    }
    _controllers.clear();
    _values.clear();
    _definitions.clear();
  }
}
