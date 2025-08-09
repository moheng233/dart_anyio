import 'package:analyzer/dart/element/element2.dart';
import 'package:build/build.dart';
import 'package:built_collection/built_collection.dart';
import 'package:code_builder/code_builder.dart';
import 'package:json_rpc_annotation/annotation.dart';
import 'package:source_gen/source_gen.dart';



abstract class BaseModelGenerator
    extends GeneratorForAnnotation<JsonRpcService> {
  static const jsonRpcMethodChecker = TypeChecker.fromUrl(
    'package:json_rpc_annotation/annotation.dart#JsonRpcMethod',
  );

  final emitter = DartEmitter(
    useNullSafetySyntax: true,
  );

  Class? generateModel(MethodElement2 method);

  @override
  Future<String?> generateForAnnotatedElement(
    Element2 element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) async {
    if (element is ClassElement2) {
      final methods = <MethodElement2>[];

      for (final method in element.methods2) {
        if (method.isPrivate && jsonRpcMethodChecker.hasAnnotationOf(method)) {
          methods.add(method);
        }
      }

      final models = <Class>[];

      for (final method in methods) {
        final classes = generateModel(method);
        if (classes != null) {
          models.add(classes);
        }
      }

      if (models.isEmpty) return null;

      return emitter
          .visitLibrary(
            Library(
              (b) => b..body = ListBuilder(models),
            ),
          )
          .toString();
    }

    return null;
  }
}
