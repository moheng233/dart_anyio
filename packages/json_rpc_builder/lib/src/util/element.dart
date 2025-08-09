import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:code_builder/code_builder.dart';

/// 转发父类构造函数参数到当前类构造函数
void forwardSuperConstructorParameters(
  ConstructorElement2 superConstructor,
  ConstructorBuilder currentConstructor,
) {
  for (final param in superConstructor.formalParameters) {
    final n = Parameter(
      (b) => b
        ..name = param.displayName
        ..toSuper = true
        ..named = param.isNamed
        ..required = param.isRequired,
    );

    if (param.isRequired) {
      currentConstructor.requiredParameters.add(n);
    } else {
      currentConstructor.optionalParameters.add(n);
    }
  }
}
