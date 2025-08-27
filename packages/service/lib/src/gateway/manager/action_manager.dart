import 'dart:async';
import 'dart:collection';

import 'package:anyio_template/service.dart';

final class ActionManager {
  ActionManager(
    this._route, {
    required HashMap<String, HashMap<String, ActionInfo>> definitions,
  }) : _definitions = definitions;

  final void Function(DeviceBaseEvent event) _route;

  Stream<ChannelBaseEvent>? _read;
  StreamSubscription<ChannelBaseEvent>? _sub;

  // key -> queue of completers
  final _pending = HashMap<String, List<Completer<bool>>>();

  // 动作定义：deviceId -> (actionId -> ActionInfo)
  final HashMap<String, HashMap<String, ActionInfo>> _definitions;

  void attach(Stream<ChannelBaseEvent> read) {
    _sub?.cancel();
    _read = read.asBroadcastStream();
    _sub = _read!.listen(_onEvent);
  }

  void _onEvent(ChannelBaseEvent event) {
    if (event is ChannelWritedEvent) {
      final key = _key(event.deviceId, event.tagId);
      final q = _pending[key];
      if (q != null && q.isNotEmpty) {
        final completer = q.removeAt(0);
        if (!completer.isCompleted) completer.complete(event.success);
        if (q.isEmpty) _pending.remove(key);
      }
    }
  }

  Future<bool> invoke(
    String deviceId,
    String actionId,
    Object? value, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    // ensure attached
    final read = _read;
    if (read == null) {
      throw StateError('ActionManager 未初始化：尚未附加 read 流');
    }

    final key = _key(deviceId, actionId);
    final completer = Completer<bool>();
    _pending.putIfAbsent(key, () => <Completer<bool>>[]).add(completer);

    // 发送写事件
    _route(DeviceActionInvokeEvent(deviceId, actionId, value));

    // 超时处理
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        // 从队列中移除自己
        final list = _pending[key];
        if (list != null) {
          list.remove(completer);
          if (list.isEmpty) _pending.remove(key);
        }
        return false;
      },
    );
  }

  // ------------ 定义管理 ------------
  /// 设置某设备的动作定义（覆盖）。
  void setActionDefinitions(
    String deviceId,
    Map<String, ActionInfo> definitions,
  ) {
    _definitions[deviceId] = HashMap.of(definitions);
  }

  /// 读取某设备的所有动作定义。
  Map<String, ActionInfo> getActionDefinitions(String deviceId) {
    final defs = _definitions[deviceId];
    if (defs == null) return const {};
    return Map<String, ActionInfo>.from(defs);
  }

  /// 读取单个动作定义。
  ActionInfo? getActionInfo(String deviceId, String actionId) {
    return _definitions[deviceId]?[actionId];
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _read = null;
    // 失败所有挂起请求
    for (final list in _pending.values) {
      for (final c in list) {
        if (!c.isCompleted) c.complete(false);
      }
    }
    _pending.clear();
    _definitions.clear();
  }

  String _key(String deviceId, String actionId) => '$deviceId::$actionId';
}
