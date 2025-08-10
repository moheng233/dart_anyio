import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:built_collection/built_collection.dart';
import 'package:code_builder/code_builder.dart' hide RecordType;

import '../../util/const.dart';
import '../../util/name.dart';
import '../../util/type.dart';
import 'base_model_generator.dart';

final class JsonRpcResponeModelGenerator extends BaseModelGenerator {
  JsonRpcResponeModelGenerator();

  /// 为 Record 类型创建响应模型
  Class _createRecordResponseModel(
    MethodElement2 method,
    DartType recordType,
  ) {
    final recordTypeAnalyzer = recordType as RecordType;

    // 获取 Record 的所有字段类型
    final fieldTypes = <String>[];

    // 处理位置字段
    for (final field in recordTypeAnalyzer.positionalFields) {
      fieldTypes.add(field.type.getDisplayString());
    }

    // 处理命名字段
    for (final field in recordTypeAnalyzer.namedFields) {
      fieldTypes.add(field.type.getDisplayString());
    }

    return Class(
      (b) => b
        ..name = getResponeModelName(method.displayName)
        ..modifier = ClassModifier.final$
        ..annotations.add(
          const InvokeExpression.newOf(jsonSerializableReference, []),
        )
        ..fields.addAll([
          for (int i = 0; i < fieldTypes.length; i++)
            Field(
              (b) => b
                ..name = 'item${i + 1}'
                ..type = Reference(fieldTypes[i])
                ..modifier = FieldModifier.final$,
            ),
        ])
        ..constructors.add(
          Constructor(
            (b) => b
              ..constant = true
              ..requiredParameters = ListBuilder([
                for (int i = 0; i < fieldTypes.length; i++)
                  Parameter(
                    (b) => b
                      ..name = 'item${i + 1}'
                      ..toThis = true,
                  ),
              ]),
          ),
        )
        ..constructors.add(
          Constructor(
            (b) => b
              ..name = 'fromJson'
              ..factory = true
              ..requiredParameters = ListBuilder([
                Parameter(
                  (b) => b
                    ..name = 'json'
                    ..type = jsonMapReference,
                ),
              ])
              ..lambda = true
              ..body = Reference(
                '_\$${normalizeElementName(method.displayName)}ResponeFromJson',
              ).call([const Reference('json')]).code,
          ),
        )
        ..methods.add(
          Method(
            (b) => b
              ..name = 'toJson'
              ..returns = jsonMapReference
              ..lambda = true
              ..body = Reference(
                '_\$${normalizeElementName(method.displayName)}ResponeToJson',
              ).call([const Reference('this')]).code,
          ),
        ),
    );
  }

  @override
  Class? generateModel(MethodElement2 method) {
    final returnType = method.returnType;

    final actualType = unwarpStreamType(unwrapFutureType(returnType));

    if (isPrimitiveType(actualType)) {
      return null;
    }

    if (isRecordType(actualType)) {
      return _createRecordResponseModel(method, actualType);
    }

    return null;
  }
}
