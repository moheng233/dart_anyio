import 'dart:async';
import 'dart:typed_data';

import 'package:dart_mappable/dart_mappable.dart';

import 'template.dart';

/// 传输通道管理类
/// > 抽象类 用于插件调用
abstract base class TransportManager {
  void register<O extends TransportOptionBase>(TransportFactoryBase<O> factory);

  TransportSession create(TransportOptionBase option);
}

typedef TransportFactory = TransportFactoryBase<TransportOptionBase>;

abstract interface class TransportFactoryBase<O extends TransportOptionBase> {
  ClassMapperBase<O> get optionMapper;

  TransportSessionBase<O> create(O option);
  String getSessionId(O option);
}

typedef TransportSession = TransportSessionBase<TransportOptionBase>;

/// > 抽象类 用于插件调用
abstract interface class TransportSessionBase<O extends TransportOptionBase> {
  Stream<Uint8List> get read;
  StreamSink<List<int>> get write;

  bool get isOpened;

  Future<void> open();
  Future<void> close();
}
