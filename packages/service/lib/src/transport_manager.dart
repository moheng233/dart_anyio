import 'dart:collection';
import 'dart:io';

import 'package:anyio_template/service.dart';

import 'transports/tcp.dart';

final class TransportManagerImpl extends TransportManager {
  final factorys = HashMap<String, TransportFactory>();
  final sessions = HashMap<String, TransportSession>();

  @override
  TransportSession create(String type, dynamic option) {
    final factory = factorys[type];
    if (factory == null) {
      throw StateError('未注册的传输类型: $type');
    }
    final sessionId = factory.getSessionId(option);
    final existed = sessions[sessionId];
    if (existed != null) return existed;
    final session = factory.create(option);
    sessions[sessionId] = session;
    return session;
  }

  @override
  dynamic loadOption(String type, Map<dynamic, dynamic> json) {
    final factory = factorys[type];
    if (factory == null) {
      throw StateError('未注册的传输类型: $type');
    }
    return factory.loadOption(json);
  }

  @override
  void register(String name, TransportFactory factory) {
    if (factorys.containsKey(name)) {
      throw StateError('传输类型已注册: $name');
    }
    factorys[name] = factory;
  }
}
