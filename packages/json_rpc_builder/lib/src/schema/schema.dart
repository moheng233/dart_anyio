import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:code_builder/code_builder.dart';

import '../util/const.dart';
import '../util/name.dart';
import '../util/type.dart';

final class RpcRouter {
  const RpcRouter(this.name, this.services);

  final String name;
  final List<RpcService> services;

  Map<String, RpcService> get serviceMap => Map.fromEntries(
    services.map(
      (e) => MapEntry(e.name, e),
    ),
  );
}

final class RpcService {
  const RpcService._(this.name, this.methods);

  factory RpcService.from(ClassElement2 classes) {
    final methods = classes.methods2.where(
      (element) =>
          element.isPrivate && jsonRpcMethodChecker.hasAnnotationOf(element),
    );

    return RpcService._(
      normalizeSeviceName(classes.displayName),
      methods.map(RpcMethod.from).toList(),
    );
  }

  final String name;
  final List<RpcMethod> methods;

  Map<String, RpcMethod> get methodMap => Map.fromEntries(
    methods.map(
      (e) => MapEntry(e.name, e),
    ),
  );
}

class RpcMethodParmamer {
  const RpcMethodParmamer({
    required this.name,
    required this.type,
    this.isNamed = false,
    this.isRequired = false,
    this.isOptional = false,
  });

  factory RpcMethodParmamer.from(FormalParameterElement element) {
    return RpcMethodParmamer(
      name: normalizeElementName(element.displayName),
      type: element.type,
      isNamed: element.isNamed,
      isRequired: element.isRequired,
      isOptional: element.isOptional,
    );
  }

  final String name;

  final DartType type;

  final bool isNamed;
  final bool isRequired;
  final bool isOptional;

  Field buildModelField() {
    return Field(
      (b) => b
        ..name = name
        ..type = Reference(type.getDisplayString())
        ..modifier = FieldModifier.final$,
    );
  }
}

sealed class RpcMethod {
  const RpcMethod(
    this.name,
    this.parameters, {
    this.isAsync = false,
  });

  factory RpcMethod.from(MethodElement2 method) {
    if (method.returnType.isDartAsyncStream) {
      return RpcSubscribeMethod.from(method);
    }

    return RpcGeneralMethod.from(method);
  }

  final String name;
  final List<RpcMethodParmamer> parameters;

  final bool isAsync;

  Class buildRequestClass() {
    return Class((b) {
      final constructor = ConstructorBuilder()..constant = true;

      b
        ..name = getRequstModelName(name)
        ..modifier = ClassModifier.final$
        ..annotations.add(
          const InvokeExpression.newOf(jsonSerializableReference, []),
        )
        ..constructors.add(constructor.build())
        ..constructors.add(
          Constructor(
            (b) => b
              ..name = 'fromJson'
              ..factory = true
              ..requiredParameters.add(
                Parameter(
                  (b) => b
                    ..name = 'json'
                    ..type = jsonMapReference,
                ),
              )
              ..lambda = true
              ..body = Reference(
                '_\$${normalizeElementName(name)}RequestFromJson',
              ).call([const Reference('json')]).code,
          ),
        );

      for (final element in parameters) {
        b.fields.add(element.buildModelField());

        constructor.requiredParameters.add(
          Parameter(
            (b) => b
              ..name = element.name
              ..toThis = true,
          ),
        );
      }
    });
  }
}

final class RpcGeneralMethod extends RpcMethod {
  const RpcGeneralMethod._(
    super.name,
    super.parameters,
    this.returnType, {
    super.isAsync,
  });

  factory RpcGeneralMethod.from(MethodElement2 method) {
    return RpcGeneralMethod._(
      normalizeElementName(method.displayName),
      method.formalParameters.map(RpcMethodParmamer.from).toList(),
      unwrapFutureType(method.returnType),
      isAsync: method.returnType.isDartAsyncFuture,
    );
  }

  final DartType returnType;
}

final class RpcSubscribeMethod extends RpcMethod {
  const RpcSubscribeMethod._(
    super.name,
    super.parameters,
    this.returnType, {
    super.isAsync,
  });

  factory RpcSubscribeMethod.from(MethodElement2 method) {
    return RpcSubscribeMethod._(
      normalizeElementName(method.displayName),
      method.formalParameters.map(RpcMethodParmamer.from).toList(),
      unwarpStreamType(unwrapFutureType(method.returnType)),
      isAsync: method.returnType.isDartAsyncFuture,
    );
  }

  final DartType returnType;
}
