import 'dart:collection';

import 'package:anyio_template/service.dart';

final class TransportManagerImpl extends TransportManager {
  final factorys = HashMap<Type, TransportFactory>();
  final sessions = HashMap<String, TransportSession>();

  @override
  TransportSession create(TransportOptionBase option) {
    final factory = factorys[option.runtimeType];

    if (factory == null) {
      throw StateError('未注册的传输类型: ${option.runtimeType}');
    }

    final sessionId = factory.getSessionId(option);
    final existed = sessions[sessionId];
    if (existed != null) return existed;
    final session = factory.create(option);
    sessions[sessionId] = session;

    return session;
  }

  @override
  void register<O extends TransportOptionBase>(
    TransportFactoryBase<O> factory,
  ) {
    if (factorys.containsKey(O)) {
      throw StateError('传输类型已注册: $O');
    }
    factorys[O] = factory;

    // 访问一下, 使其Mapper生效
    factory.optionMapper;
  }
}
