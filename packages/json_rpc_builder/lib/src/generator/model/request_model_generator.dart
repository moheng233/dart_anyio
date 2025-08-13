import 'package:analyzer/dart/element/element2.dart';
import 'package:built_collection/built_collection.dart';
import 'package:code_builder/code_builder.dart';

import '../../util/const.dart';
import '../../util/element.dart';
import '../../util/name.dart';
import 'base_model_generator.dart';

final class JsonRpcRequestModelGenerator extends BaseModelGenerator {
  JsonRpcRequestModelGenerator();

  @override
  Class? generateModel(MethodElement2 method) {
    if (method.formalParameters.isEmpty) {
      return null;
    }

    return Class(
      (b) => b
        ..name = getRequstModelName(method.displayName, withPrive: true)
        ..modifier = ClassModifier.final$
        ..annotations = ListBuilder([
          const InvokeExpression.newOf(jsonSerializableReference, []),
        ])
        ..fields = ListBuilder(<Field>[
          for (final parameter in method.formalParameters)
            Field(
              (b) => b
                ..name = parameter.name3
                ..type = parameter.type.reference
                ..modifier = FieldModifier.final$,
            ),
        ])
        ..constructors.add(
          Constructor(
            (b) => b
              ..constant = true
              ..optionalParameters = ListBuilder(<Parameter>[
                for (final parameter in method.formalParameters)
                  Parameter(
                    (b) => b
                      ..name = parameter.displayName
                      ..named = true
                      ..required = parameter.isRequired
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
              ..requiredParameters = ListBuilder(<Parameter>[
                Parameter(
                  (b) => b
                    ..name = 'json'
                    ..type = jsonMapReference,
                ),
              ])
              ..lambda = true
              ..body = Reference(
                '_\$${getRequstModelName(method.displayName)}FromJson',
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
                '_\$${getRequstModelName(method.displayName)}ToJson',
              ).call([const Reference('this')]).code,
          ),
        ),
    );
  }
}
