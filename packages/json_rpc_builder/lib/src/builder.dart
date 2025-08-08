import 'dart:math';

import 'package:analyzer/dart/element/element2.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:dart_style/dart_style.dart';
import 'package:json_rpc_annotation/annotation.dart';
import 'package:source_gen/source_gen.dart';

final class JsonRpcBuilder extends GeneratorForAnnotation<JsonRpcService> {
  static const jsonRpcMethodChecker = TypeChecker.fromUrl(
    'package:json_rpc_annotation/annotation.dart#JsonRpcMethod',
  );

  final formatter = DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
  );

  final emitter = DartEmitter();

  @override
  Future<String?> generateForAnnotatedElement(
    Element2 element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) async {
    if (element is ClassElement2) {
      for (final methods in element.methods2) {
        if (methods.isPrivate &&
            jsonRpcMethodChecker.hasAnnotationOf(methods)) {}
      }

      final mixin = Class(
        (b) => b
          ..name = '_\$${element.displayName}'
          ..mixin = true,
      );

      return formatter.format('${mixin.accept(emitter)}');
    }

    return null;
  }
}
