import 'dart:async';
import 'dart:io';

import 'package:checked_yaml/checked_yaml.dart';
import 'package:path/path.dart' as path;
import 'package:anyio_service/service.dart';
import 'package:anyio_adapter_modbus/src/protocol.dart';
import 'package:anyio_adapter_modbus/src/template.dart';
import 'package:anyio_template/service.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: anyio <device_config.yaml> <templates_directory> [http_port]');
    exit(1);
  }

  final deviceFile = File(args[0]);
  final templateDirectory = Directory(args[1]);
  final httpPort = args.length > 2 ? int.tryParse(args[2]) ?? 8080 : 8080;

  if (!await deviceFile.exists()) {
    print('Device configuration file not found: ${deviceFile.path}');
    exit(1);
  }

  if (!await templateDirectory.exists()) {
    print('Template directory not found: ${templateDirectory.path}');
    exit(1);
  }

  print('Starting AnyIO Service...');
  print('Device config: ${deviceFile.path}');
  print('Template directory: ${templateDirectory.path}');
  print('HTTP API port: $httpPort');

  // Initialize managers
  final transportManager = TransportManagerImpl();
  final channelManager = ChannelManagerImpl();

  // Register transport factories
  transportManager.register(TransportFactoryForTcpImpl());

  // Register channel factories
  channelManager.registerFactory(ChannelFactoryForModbus());

  // Create service manager
  final serviceManager = ServiceManager(
    channelManager: channelManager,
    transportManager: transportManager,
  );

  // Initialize time-series database
  final timeSeriesDb = InMemoryTimeSeriesDatabase();
  final dataCollector = DataCollector(timeSeriesDb: timeSeriesDb);

  // Create HTTP API server
  final httpServer = HttpApiServer(
    serviceManager: serviceManager,
    timeSeriesDb: timeSeriesDb,
    port: httpPort,
  );

  try {
    // Load configuration and templates
    print('Loading service configuration...');
    final serviceConfig = await serviceManager.loadServiceConfig(deviceFile);
    
    print('Loading device templates...');
    final templates = await serviceManager.loadTemplates(templateDirectory);
    
    print('Found ${templates.length} templates: ${templates.keys.join(', ')}');
    print('Found ${serviceConfig.devices.length} devices');

    // Start data collector
    print('Starting data collector...');
    await dataCollector.start();

    // Start service
    print('Starting devices...');
    await serviceManager.start(serviceConfig, templates);

    // Setup data collection from devices
    for (final device in serviceManager.devices) {
      // Listen to channel events for this device
      final session = serviceManager.getChannelSession(device.deviceId);
      if (session != null) {
        session.read.listen((event) {
          if (event is ChannelUpdateEvent && event.deviceId == device.deviceId) {
            for (final point in event.updates) {
              dataCollector.collectPoint(point.deviceId, point.tagId, point.value);
            }
          }
        });
      }
    }

    // Start HTTP API server
    print('Starting HTTP API server...');
    unawaited(httpServer.start());

    print('AnyIO Service started successfully!');
    print('Available endpoints:');
    print('  GET  http://localhost:$httpPort/health');
    print('  GET  http://localhost:$httpPort/devices');
    print('  GET  http://localhost:$httpPort/devices/{deviceId}');
    print('  GET  http://localhost:$httpPort/devices/{deviceId}/values');
    print('  GET  http://localhost:$httpPort/devices/{deviceId}/points');
    print('  GET  http://localhost:$httpPort/devices/{deviceId}/points/{pointId}');
    print('  POST http://localhost:$httpPort/devices/{deviceId}/write');
    print('  GET  http://localhost:$httpPort/history/{deviceId}[/{pointId}]?start=...&end=...&limit=...');
    print('  GET  http://localhost:$httpPort/stats');

    // Handle shutdown gracefully
    ProcessSignal.sigint.watch().listen((_) async {
      print('\nShutting down...');
      await httpServer.stop();
      await dataCollector.stop();
      await serviceManager.stop();
      print('Service stopped.');
      exit(0);
    });

    ProcessSignal.sigterm.watch().listen((_) async {
      print('\nShutting down...');
      await httpServer.stop();
      await dataCollector.stop();
      await serviceManager.stop();
      print('Service stopped.');
      exit(0);
    });

    // Keep the service running
    await Completer<void>().future;

  } catch (e, stackTrace) {
    print('Failed to start service: $e');
    print('Stack trace: $stackTrace');
    
    // Cleanup on error
    try {
      await httpServer.stop();
      await dataCollector.stop();
      await serviceManager.stop();
    } catch (cleanupError) {
      print('Error during cleanup: $cleanupError');
    }
    
    exit(1);
  }
}
