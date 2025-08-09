import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:dart_style/dart_style.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:json_rpc_annotation/annotation.dart';
import 'package:source_gen/source_gen.dart';

import '../../util/const.dart';
import '../../util/element.dart';
import '../../util/name.dart';
import '../../util/type.dart';

final class JsonRpcServerGenerator
    extends GeneratorForAnnotation<JsonRpcService> {
  static const jsonSerializableChecker = TypeChecker.fromRuntime(
    JsonSerializable,
  );

  static const jsonRpcMethodChecker = TypeChecker.fromUrl(
    'package:json_rpc_annotation/annotation.dart#JsonRpcMethod',
  );

  final emitter = DartEmitter(
    useNullSafetySyntax: true,
  );

  @override
  Future<String?> generateForAnnotatedElement(
    Element2 element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) async {
    if (element is ClassElement2 && element.isAbstract && element.isInterface) {
      final methods = element.methods2.where(
        (element) =>
            element.isPrivate && jsonRpcMethodChecker.hasAnnotationOf(element),
      );

      if (methods.isEmpty) return null;

      final mixin = Class(
        (b) => b
          ..name = '${normalizeSeviceName(element.displayName)}ServerService'
          ..modifier = ClassModifier.interface
          ..abstract = true
          ..implements.add(Reference(element.displayName))
          ..implements.add(
            const Reference(
              'IJsonRpcService',
              'package:json_rpc_runtime/runtime.dart',
            ),
          )
          ..constructors.add(
            Constructor(
              (b) {
                final constructor = element.unnamedConstructor2;
                const peerRef = Reference('peer');

                Expression registerMethod = peerRef;

                for (final method in methods) {
                  registerMethod = registerMethod.cascade('registerMethod').call([
                    literalString(
                      '${normalizeElementName(element.displayName)}/${normalizeElementName(method.displayName)}',
                    ),
                    Reference('${method.displayName}_Pre'),
                  ]);
                }

                b
                  ..requiredParameters.add(
                    Parameter(
                      (b) => b
                        ..name = 'peer'
                        ..toThis = true,
                    ),
                  )
                  ..body = Block((b) => b..addExpression(registerMethod));

                if (constructor != null) {
                  forwardSuperConstructorParameters(constructor, b);
                }
              },
            ),
          )
          ..fields.add(
            Field(
              (b) => b
                ..name = 'peer'
                ..modifier = FieldModifier.final$
                ..type = JsonRpcPeerReference
                ..annotations.add(const Reference('override')),
            ),
          )
          ..methods.addAll([
            for (final method in methods)
              Method(
                (b) => b
                  ..name = '${method.displayName}_Pre'
                  ..modifier = MethodModifier.async
                  ..requiredParameters.add(
                    Parameter(
                      (b) => b
                        ..name = 'request'
                        ..type = parametersReference,
                    ),
                  )
                  ..returns = jsonMapFutureReference
                  ..body = Block(
                    (b) {
                      final returned = unwrapFutureType(method.returnType);

                      final exec = InvokeExpression.newOf(
                        Reference(method.displayName),
                        [
                          for (final param in method.formalParameters.where(
                            (element) => element.isPositional,
                          ))
                            const Reference(
                              'requestModel',
                            ).property(param.displayName),
                        ],
                        Map.fromEntries([
                          for (final param in method.formalParameters.where(
                            (element) => element.isNamed,
                          ))
                            MapEntry(
                              param.displayName,
                              const Reference(
                                'requestModel',
                              ).property(param.displayName),
                            ),
                        ]),
                        [
                          for (final param in method.formalParameters.where(
                            (element) => element.isOptional,
                          ))
                            Reference(
                              'requestModel.${param.displayName}',
                            ),
                        ],
                      );

                      b.statements.addAll(
                        <Expression>[
                          if (method.formalParameters.isNotEmpty)
                            declareFinal(
                              'requestModel',
                            ).assign(
                              InvokeExpression.newOf(
                                Reference(
                                  getRequstModelName(method.displayName),
                                ),
                                [const Reference('request').property('asMap')],
                                {},
                                [],
                                'fromJson',
                              ),
                            ),
                          declareFinal('result').assign(
                            method.returnType.isDartAsyncFuture ||
                                    method.returnType.isDartAsyncFutureOr
                                ? exec.awaited
                                : exec,
                          ),
                          if (returned is VoidType)
                            literalConstMap({}).returned
                          else if (isPrimitiveType(returned))
                            literalMap({
                              'value': const Reference('result'),
                            }).returned
                          else
                            const Reference(
                              'result',
                            ).property('toJson').call([]).returned,
                        ].map(
                          (e) => e.statement,
                        ),
                      );
                    },
                  ),
              ),
          ]),
      );

      return emitter.visitClass(mixin).toString();
    }

    return null;
  }
}
