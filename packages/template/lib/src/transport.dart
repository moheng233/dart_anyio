import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_mappable/dart_mappable.dart';

/// 传输通道管理类
/// > 抽象类 用于插件调用
abstract base class TransportManager {
  void register(String name, TransportFactoryBase<dynamic> factory);

  dynamic loadOption(String type, Map<dynamic, dynamic> json);
  TransportSessionBase<dynamic> create(String type, dynamic option);
}

typedef TransportFactory = TransportFactoryBase<Object>;

abstract interface class TransportFactoryBase<O extends Object> {
  ClassMapperBase<O> get optionMapper;

  TransportSessionBase<O> create(O option);
  String getSessionId(O option);
}

typedef TransportSession = TransportSessionBase<dynamic>;

/// > 抽象类 用于插件调用
abstract interface class TransportSessionBase<O> {
  Stream<Uint8List> get read;
  StreamSink<List<int>> get write;

  bool get isOpened;

  Future<void> open();
  Future<void> close();
}
