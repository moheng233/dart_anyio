// This is a dev-only CLI to dump JSON Schemas for config validation.
// ignore_for_file: directives_ordering

import 'dart:io';

import 'package:anyio_adapter_modbus/src/template.dart';
import 'package:anyio_template/service.dart';
import 'package:dart_mappable_schema/json_schema.dart';

void main(List<String> args) {
  // Ensure mappers are initialized so schemas include discriminators
  ServiceOptionMapper.ensureInitialized();
  TemplateOptionMapper.ensureInitialized();
  ChannelOptionForModbusMapper.ensureInitialized();
  ChannelTemplateForModbusMapper.ensureInitialized();

  stdout.writeln(
    TemplateOptionMapper.ensureInitialized().toJsonSchema().toJson(),
  );
}
