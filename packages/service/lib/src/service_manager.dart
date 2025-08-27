import 'dart:async';
import 'dart:io';

import 'package:anyio_template/service.dart';
import 'package:checked_yaml/checked_yaml.dart';
import 'package:path/path.dart' as path;

import 'gateway/data_gateway.dart';

/// Service gateway manager that orchestrates the entire system
final class ServiceManager {
  ServiceManager({
    required DataGateway channelManager,
  }) : gateway = channelManager;

  final DataGateway gateway;

  /// Load service configuration from file
  static Future<ServiceOption> loadServiceConfig(File configFile) async {
    final content = await configFile.readAsString();
    return checkedYamlDecode(
      content,
      (json) => ServiceOptionMapper.fromMap(json!.cast<String, dynamic>()),
    );
  }

  /// Load device templates from directory
  static Future<Map<String, TemplateOption>> loadTemplates(
    Directory templateDir,
  ) async {
    final templates = <String, TemplateOption>{};

    await for (final entity in templateDir.list()) {
      if (entity is File && path.extension(entity.path) == '.yaml') {
        final templateName = path.basenameWithoutExtension(entity.path);
        final content = await entity.readAsString();
        final template = checkedYamlDecode(
          content,
          (json) => TemplateOptionMapper.fromMap(json!.cast<String, dynamic>()),
        );
        templates[templateName] = template;
      }
    }

    return templates;
  }
}
