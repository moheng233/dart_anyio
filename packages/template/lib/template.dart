import 'dart:io';

import 'package:checked_yaml/checked_yaml.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:path/path.dart' as p;

import 'src/template.dart';

export 'src/connects/modbus.dart';
export 'src/template.dart';

final class TemplateLoader {
  TemplateLoader(this.templateDirectroy);

  final Directory templateDirectroy;

  final _templatesCache = <String, Template>{};

  Future<(Iterable<Template>, Map<String, CheckedFromJsonException>)>
  loadAllTemplate({bool enforce = false}) async {
    if (enforce == false && _templatesCache.isNotEmpty) {
      return (_templatesCache.values, <String, CheckedFromJsonException>{});
    }

    _templatesCache.clear();
    final exceptions = <String, CheckedFromJsonException>{};

    final files = await templateDirectroy
        .list()
        .where((event) => event is File)
        .cast<File>()
        .where((event) => p.extension(event.path) == '.yaml')
        .toList();

    for (final file in files) {
      try {
        final template = checkedYamlDecode(
          await file.readAsString(),
          (map) => map != null ? Template.fromJson(map) : null,
        );

        if (template != null) {
          _templatesCache[file.path] = template;
        }
      } on CheckedFromJsonException catch (e) {
        exceptions[file.path] = e;
      }
    }

    return (_templatesCache.values, exceptions);
  }
}
