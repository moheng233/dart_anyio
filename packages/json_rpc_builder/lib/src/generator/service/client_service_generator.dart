import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:json_rpc_annotation/annotation.dart';
import 'package:source_gen/source_gen.dart';

import '../../util/const.dart';
import '../../util/element.dart';
import '../../util/name.dart';
import '../../util/type.dart';

const _jsonRpcClientBaseReference = Reference('IJsonRpcClient');

final class JsonRpcClientGenerator
    extends GeneratorForAnnotation<JsonRpcService> {
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

      final classes = Class(
        (b) => b
          ..name = '${normalizeSeviceName(element.displayName)}Client'
          ..modifier = ClassModifier.final$
          ..implements.add(_jsonRpcClientBaseReference)
          ..constructors.add(
            Constructor(
              (b) {
                b.requiredParameters.add(
                  Parameter(
                    (b) => b
                      ..name = 'peer'
                      ..toThis = true,
                  ),
                );
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
          ..methods.addAll(
            methods.map(
              (e) => Method(
                (b) => b
                  ..name = normalizeElementName(e.displayName)
                  ..modifier = MethodModifier.async
                  ..cloneParametersFromElement(e)
                  ..cloneReturnTypeFromElement(e, withFuture: true)
                  ..body = Block(
                    (b) {
                      final returned = unwrapFutureType(e.returnType);

                      if (e.formalParameters.isNotEmpty) {
                        b.addExpression(
                          declareFinal('request').assign(
                            refer(
                              getRequstModelName(
                                e.displayName,
                                withPrive: true,
                              ),
                            ).newInstance(
                              [],
                              Map.fromEntries(
                                e.formalParameters.map(
                                  (e) => MapEntry(
                                    e.displayName,
                                    Reference(e.displayName),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      b.addExpression(
                        declareFinal('respone').assign(
                          refer('peer')
                              .property('sendRequest')
                              .call([
                                literalString(
                                  '${normalizeElementName(element.displayName)}/${normalizeElementName(e.displayName)}',
                                ),
                                if (e.formalParameters.isNotEmpty)
                                  refer('request').property('toJson').call([]),
                              ])
                              .awaited
                              .asA(jsonMapReference),
                        ),
                      );

                      if (returned is VoidType) {
                      } else if (isPrimitiveType(returned)) {
                        b.addExpression(
                          refer('respone')
                              .index(literalString('value'))
                              .asA(refer(returned.getDisplayString()))
                              .returned,
                        );
                      } else {
                        b.addExpression(
                          refer(
                            returned.getDisplayString(),
                          ).property('fromJson').call([
                            refer('respone'),
                          ]).returned,
                        );
                      }
                    },
                  ),
              ),
            ),
          ),
      );

      return emitter.visitClass(classes).toString();
    }

    return null;
  }
}
