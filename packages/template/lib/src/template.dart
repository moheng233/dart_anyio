import 'package:freezed_annotation/freezed_annotation.dart';

part 'template.freezed.dart';

@freezed
abstract class Template with _$Template {
  const factory Template(
    String name,
    String version,
    Schema schema,
  ) = _Template;

  factory Template.fromJson(Map<String, dynamic> json) => _$TemplateFromJson(json);
}

@Freezed(unionKey: 'type')
sealed class Schema with _$Schema {
  const factory Schema.modbus() = SchemaForModbus;
}
