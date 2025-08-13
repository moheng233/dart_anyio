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

extension DartTypeBuilderHelper on DartType {
  Reference get reference => Reference(getDisplayString());
}

extension FormalParametersBuilderHelper on FormalParameterElement {
  Parameter get builder => Parameter(
    (b) => b
      ..name = displayName
      ..type = type.reference
      ..types.addAll(typeParameters2.references)
      ..named = isNamed
      ..required = isRequiredNamed,
  );
}

extension MethodBuilderHelper on MethodBuilder {
  void cloneParametersFromElement(MethodElement2 method) {
    for (final param in method.formalParameters) {
      if (param.isPositional) {
        requiredParameters.add(param.builder);
      } else {
        optionalParameters.add(param.builder);
      }
    }
  }

  void cloneReturnTypeFromElement(
    MethodElement2 method, {
    bool withFuture = false,
  }) {
    var ref = method.returnType.reference;
  
    if (withFuture) {
      if (!method.returnType.isDartAsyncFuture) {
        ref = TypeReference((b) => b..symbol = 'Future'..types.add(ref));
      }
    }

    returns = ref;
  }
}

extension TypeParametersBuilderHelper on List<TypeParameterElement2> {
  Iterable<Reference> get references => map(
    (e) => Reference(e.displayName),
  );
}
