@MappableLib(caseStyle: CaseStyle.snakeCase)
library;

import 'package:dart_mappable/dart_mappable.dart';

import 'point.dart';

part 'template.mapper.dart';

@MappableClass()
final class ServiceOption with ServiceOptionMappable {
  const ServiceOption(
    this.devices,
  );

  final List<DeviceOption> devices;
}

@MappableClass()
final class TemplateOption with TemplateOptionMappable {
  const TemplateOption({
    required this.info,
    required this.template,
    required this.points,
    this.meta = const {},
  });

  final ChannelTempateInfo info;
  final Map<String, Object?> meta;
  final ChannelTemplateBase template;
  final Map<String, VariableInfo> points;
}

@MappableClass(discriminatorKey: 'type')
base class TransportOptionBase with TransportOptionBaseMappable {
  const TransportOptionBase();
}

@MappableClass(discriminatorKey: 'type')
base class ChannelOptionBase with ChannelOptionBaseMappable {
  const ChannelOptionBase();
}

@MappableClass(discriminatorKey: 'type')
base class ChannelTemplateBase with ChannelTemplateBaseMappable {
  const ChannelTemplateBase();
}

@MappableClass()
final class ChannelTempateInfo with ChannelTempateInfoMappable {
  const ChannelTempateInfo({
    required this.name,
    required this.version,
    this.displayName = const {},
  });

  final String name;
  final String version;
  final Map<String, String> displayName;
}

@MappableClass()
final class DeviceOption with DeviceOptionMappable {
  const DeviceOption({
    required this.name,
    required this.template,
    required this.channel,
    this.displayName,
    this.meta = const {},
  });

  final String name;
  final String template;
  final ChannelOptionBase channel;
  final String? displayName;
  final Map<String, Object?> meta;
}
