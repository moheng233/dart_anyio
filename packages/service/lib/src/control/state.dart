import 'dart:async';

import 'package:meta/meta.dart';

@immutable
final class StateValue {}

@immutable
final class StateKey<V extends StateValue> {
  const StateKey(this.namespace, this.name);

  final String namespace;
  final String name;

  String get fullName => '$namespace/$name';
}

typedef StateChangePair = ({StateKey<StateValue> key, Object? value});

final class StateContainer {
  final _keyMap = <StateKey<StateValue>, Object?>{};
  final _nameMap = <String, StateKey<StateValue>>{};

  final _events = StreamController<StateChangePair>();

  V? getState<V extends StateValue>(StateKey<V> key) {
    return _keyMap[key] as V?;
  }
}
