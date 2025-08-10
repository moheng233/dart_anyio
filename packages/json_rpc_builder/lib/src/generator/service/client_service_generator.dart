import 'package:analyzer/dart/element/element2.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:json_rpc_annotation/annotation.dart';
import 'package:source_gen/source_gen.dart';

import '../../util/name.dart';

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
      final classes = Class(
        (b) => b
          ..name = '${normalizeSeviceName(element.displayName)}Client'
          ..modifier = ClassModifier.final$
          ..extend = _jsonRpcClientBaseReference,
      );

      return emitter.visitClass(classes).toString();
    }

    return null;
  }
}
