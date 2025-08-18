import 'dart:async';
import 'dart:io';

import 'package:checked_yaml/checked_yaml.dart';
import 'package:path/path.dart' as path;
import 'package:anyio_service/src/transports/tcp.dart';
import 'package:anyio_adapter_modbus/src/protocol.dart';
import 'package:anyio_adapter_modbus/src/template.dart';
import 'package:anyio_template/service.dart';

void main(List<String> args) async {
  print(args);

  final deviceFile = File(args[0]);
  final templateDirectory = Directory(args[1]);

  final templates = Map.fromEntries(
    await templateDirectory
        .list()
        .where(
          (event) => event is File,
        )
        .cast<File>()
        .where(
          (event) => path.extension(event.path) == '.yaml',
        )
        .map(
          (event) => MapEntry(path.basenameWithoutExtension(event.path), event),
        )
        .toList(),
  );

  final devices = checkedYamlDecode(
    await deviceFile.readAsString(),
    (json) => ServiceOption.fromJson(json!),
  );

  for (final device in devices.devices) {
    late final TransportSession transport;

    switch (device.transport) {
      case 'tcp':
        transport = TransportForTcpImpl(
          TransportOptionForTcp.fromJson(device.transportOption),
        );
    }

    
  }
}
