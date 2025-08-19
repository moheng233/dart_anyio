import 'package:dart_mappable/dart_mappable.dart';

part 'template.mapper.dart';

@MappableClass()
final class ServiceOption with ServiceOptionMappable {
  const ServiceOption(
    this.devices,
  );

  final List<DeviceOption> devices;
}

@MappableClass(discriminatorKey: 'adapter')
base class TransportOptionBase with TransportOptionBaseMappable {
  const TransportOptionBase();
}

@MappableClass(discriminatorKey: 'adapter')
base class ChannelOptionBase with ChannelOptionBaseMappable {
  const ChannelOptionBase();
}

@MappableClass(discriminatorKey: 'adapter')
base class ChannelTemplateBase with ChannelTemplateBaseMappable {
  const ChannelTemplateBase(this.name, this.version);

  final String name;
  final String version;
}

@MappableClass()
abstract class DeviceOption with DeviceOptionMappable {
  const DeviceOption({
    required this.name,
    required this.template,
    required this.channelOption,
    required this.transportOption,
    this.displayName,
  });

  final String name;
  final String template;
  final ChannelOptionBase channelOption;
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
