import 'package:freezed_annotation/freezed_annotation.dart';

import 'connects/modbus.dart';

part 'template.freezed.dart';
part 'template.g.dart';

@freezed
abstract class Template with _$Template {
  const factory Template(
    String name,
    String version,
    Schema schema,
  ) = _Template;

  factory Template.fromJson(Map<dynamic, dynamic> json) =>
      _$TemplateFromJson(json);
}

@Freezed(unionKey: 'type')
sealed class Schema with _$Schema {
  const factory Schema.modbus({
    required List<ModbusPoll> pools,
    required Map<String, ModbusReadPoint> reads,
    required Map<String, ModbusWritePoint> writes,
  }) = SchemaForModbus;
  const factory Schema.can() = SchemaForCan;

  factory Schema.fromJson(Map<String, dynamic> json) => _$SchemaFromJson(json);
}
