// ignore_for_file: avoid_print bin

import 'dart:async';
import 'dart:io';

import 'package:anyio_adapter_modbus/adapter.dart';
import 'package:anyio_service/service.dart';
import 'package:anyio_service/src/database/impls/questdb.dart';
import 'package:anyio_template/service.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    print(
      'Usage: anyio <device_config.yaml> <templates_directory> [http_port]',
    );
    exit(1);
  }

  final deviceFile = File(args[0]);
  final templateDirectory = Directory(args[1]);
  final httpPort = args.length > 2 ? int.tryParse(args[2]) ?? 8080 : 8080;

  if (!deviceFile.existsSync()) {
    print('Device configuration file not found: ${deviceFile.path}');
    exit(1);
  }

  if (!templateDirectory.existsSync()) {
    print('Template directory not found: ${templateDirectory.path}');
    exit(1);
  }

  print('Starting AnyIO Service...');
  print('Device config: ${deviceFile.path}');
  print('Template directory: ${templateDirectory.path}');
  print('HTTP API port: $httpPort');

  // Register channel factory (Modbus) with new handler + mappers
  DataGateway.registerFactory(
    'modbus',
    modbusChannelFactoryHandler,
    channelOptionMapper: ChannelOptionForModbusMapper.ensureInitialized(),
    templateOptionMapper: ChannelTemplateForModbusMapper.ensureInitialized(),
  );

  try {
    // Load configuration and templates
    print('Loading service configuration...');
    final serviceConfig = await ServiceManager.loadServiceConfig(deviceFile);

    print('Loading device templates...');
    final templates = await ServiceManager.loadTemplates(templateDirectory);

    print('Found ${templates.length} templates: ${templates.keys.join(', ')}');
    print('Found ${serviceConfig.devices.length} devices');

    // Initialize channels (spawn adapter isolates and sessions)
    print('Starting channels...');
    final channelManager = await DataGateway.initialize(
      serviceConfig,
      templates,
    );

    // Initialize QuestDB clients
    print('Initializing QuestDB clients...');

    // Create QuestDB database implementation using factory
    final questDbImpl = await RecordDatabaseQuestDBImpl.create(
      serverIp: 'localhost',
      variableDefinitions: <String, Map<String, VariableInfo>>{},
      actionDefinitions: <String, Map<String, ActionInfo>>{},
    );

    // Initialize database tables
    print('Initializing database tables...');
    await questDbImpl.initialize();

    // Listen to performance events and store them in QuestDB
    channelManager.listenEvent<ChannelPerformanceEvent>().listen((event) async {
      try {
        if (event is ChannelPerformanceCountEvent) {
          if (event.count != null) {
            await questDbImpl.addPerformanceCountEvent(
              event.eventName,
              event.count!,
            );
          }
        } else if (event is ChannelPerformanceTimeEvent) {
          if (event.startTime != null && event.endTime != null) {
            await questDbImpl.addPerformanceRangeEvent(
              event.eventName,
              event.startTime!,
              event.endTime!,
            );
          }
        }
      } on Exception catch (e) {
        print('Failed to store performance event: $e');
      }
    });

    // Create service manager
    final serviceManager = ServiceManager(
      channelManager: channelManager,
    );

    // Start HTTP API server
    final httpServer = HttpApiServer(
      serviceManager: serviceManager,
      port: httpPort,
    );
    print('Starting HTTP API server...');
    unawaited(httpServer.start());

    print('AnyIO Service started successfully!');
    print('Available endpoints:');
    print('  GET  http://localhost:$httpPort/health');
    print('  GET  http://localhost:$httpPort/devices');
    print('  GET  http://localhost:$httpPort/devices/{deviceId}');
    print('  GET  http://localhost:$httpPort/devices/{deviceId}/status');
    print('  GET  http://localhost:$httpPort/devices/{deviceId}/values');
    print('  GET  http://localhost:$httpPort/devices/{deviceId}/variables');
    print(
      '  GET  http://localhost:$httpPort/devices/{deviceId}/variables/{variableId}',
    );
    print(
      '  POST http://localhost:$httpPort/devices/{deviceId}/variables/{variableId}',
    );
    print('');
    print('Channel isolation: via per-adapter isolates');

    // Handle shutdown gracefully
    // ProcessSignal.sigint.watch().listen((_) async {
    //   print('\nShutting down...');
    //   await httpServer.stop();
    //   await dataCollector.stop();
    //   await serviceManager.stop();
    //   print('Service stopped.');
    //   exit(0);
    // });

    // ProcessSignal.sigterm.watch().listen((_) async {
    //   print('\nShutting down...');
    //   await httpServer.stop();
    //   await dataCollector.stop();
    //   await serviceManager.stop();
    //   print('Service stopped.');
    //   exit(0);
    // });

    // Keep the service running
    await Completer<void>().future;
  } on Exception catch (e, stackTrace) {
    print('Failed to start service: $e');
    print('Stack trace: $stackTrace');

    // Cleanup on error (best-effort)
    // No resources to dispose here as server may not have started

    exit(1);
  }
}
