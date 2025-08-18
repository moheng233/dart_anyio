import 'package:analyzer/dart/element/element2.dart';
import 'package:build/src/builder/build_step.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:source_gen/source_gen.dart';

final class JsonSchemaGenerator
    extends GeneratorForAnnotation<JsonSerializable> {
  @override
  dynamic generateForAnnotatedElement(
    Element2 element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is ClassElement2) {
      
    }
  }
}
