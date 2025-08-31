@MappableLib(caseStyle: CaseStyle.snakeCase)
library;

import 'package:dart_mappable/dart_mappable.dart';
import 'package:meta/meta.dart';

part 'point.mapper.dart';

@MappableEnum()
enum VariableType { bool, int, uint, float }

@immutable
@MappableClass()
class Variable with VariableMappable {
  const Variable(this.deviceId, this.tagId, this.value);

  final String deviceId;
  final String tagId;
  final Object? value;
}

@immutable
@MappableClass()
class VariableId with VariableIdMappable {
  const VariableId(this.deviceId, this.tagId);

  final String deviceId;
  final String tagId;
}

@immutable
@MappableClass()
class ActionId with ActionIdMappable {
  const ActionId(this.deviceId, this.actionId);

  final String deviceId;
  final String actionId;
}

@MappableClass(discriminatorKey: 'type')
sealed class VariableInfo with VariableInfoMappable {
  const VariableInfo({this.displayName, this.detailed, this.unit});

  final String? displayName;
  final String? detailed;
  final String? unit;
}

@MappableClass(discriminatorKey: 'type')
sealed class ActionInfo with ActionInfoMappable {
  const ActionInfo({
    this.displayName,
    this.detailed,
  });

  final String? displayName;
  final String? detailed;
}

@MappableClass(discriminatorValue: 'value')
final class VariableInfoForValue extends VariableInfo
    with VariableInfoForValueMappable {
  const VariableInfoForValue({
    this.read,
    super.displayName,
    super.detailed,
  });

  final String? read;
}

@MappableClass(discriminatorValue: 'value')
final class ActionInfoForValue extends ActionInfo
    with ActionInfoForValueMappable {
  const ActionInfoForValue({
    this.write,
    super.displayName,
    super.detailed,
  });

  final String? write;
}

@MappableClass(discriminatorValue: 'enum')
final class VariableInfoForEnum extends VariableInfo
    with VariableInfoForEnumMappable {
  VariableInfoForEnum({
    required this.values,
    super.displayName,
    super.detailed,
  });

  final Map<String, num> values;
}

@MappableClass(discriminatorValue: 'enum')
final class ActionInfoForEnum extends ActionInfo
    with ActionInfoForEnumMappable {
  ActionInfoForEnum({
    required this.values,
    super.displayName,
    super.detailed,
  });

  final Map<String, num> values;
}
