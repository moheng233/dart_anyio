import 'package:dart_mappable/dart_mappable.dart';

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
    required this.meta,
    required this.tempate,
  });

  final ChannelTempateInfo info;
  final Map<String, dynamic> meta;
  final ChannelTemplateBase tempate;
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
abstract class DeviceOption with DeviceOptionMappable {
  const DeviceOption({
    required this.name,
    required this.template,
    required this.channel,
    required this.transportOption,
    this.displayName,
  });

  final String name;
  final String template;
  final ChannelOptionBase channel;
  final TransportOptionBase transportOption;
  final String? displayName;
}

@MappableClass()
abstract class PointInfo with PointInfoMappable {
  const PointInfo({required this.tag, this.displayName, this.detailed});

  final String tag;
  final String? displayName;
  final String? detailed;
}
