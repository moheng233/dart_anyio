import 'dart:io';

import 'package:anyio_service/service.dart';

/// Example demonstrating logging and performance monitoring features
Future<void> main() async {
  // Initialize logging system with both console and file logging
  final consoleLogger = ConsoleLogger(globalLevel: LogLevel.info);
  final fileLogger = FileLogger(
    logFilePath: 'logs/service.log',
    globalLevel: LogLevel.debug,
  );
  final multiLogger = MultiLogger([consoleLogger, fileLogger]);
  
  // Initialize performance monitoring
  final performanceMonitor = PerformanceMonitor(maxHistorySize: 1000);
  
  // Create service manager with logging and performance monitoring
  final serviceManager = ServiceManager(
    channelManager: ChannelManagerImpl(useIsolatedChannels: true),
    transportManager: TransportManagerImpl(),
    enableChannelRestart: true,
    maxRestartAttempts: 3,
    restartDelaySeconds: 5,
    logger: multiLogger,
    performanceMonitor: performanceMonitor,
    performanceThresholds: {
      PerformanceOperationType.poll: Duration(milliseconds: 100),
      PerformanceOperationType.write: Duration(milliseconds: 50),
    },
  );

  print('=== Logging and Performance Monitoring Demo ===\n');

  // Configure device-specific log levels
  serviceManager.setDeviceLogLevel('device1', LogLevel.debug);
  serviceManager.setDeviceLogLevel('device2', LogLevel.warn);
  serviceManager.setGlobalLogLevel(LogLevel.info);

  print('Configured log levels:');
  print('- device1: DEBUG');
  print('- device2: WARN');
  print('- global: INFO\n');

  // Simulate some service operations
  await _demonstrateLogging(serviceManager);
  await _demonstratePerformanceMonitoring(serviceManager);

  print('\n=== Demo completed ===');
}

Future<void> _demonstrateLogging(ServiceManager serviceManager) async {
  print('=== Logging Features Demo ===');
  
  // Access the logger directly
  final logger = LoggingManager.instance.logger;
  
  // Test different log levels
  logger.trace('This is a trace message', deviceId: 'device1');
  logger.debug('Device configuration loaded', 
               deviceId: 'device1', 
               context: {'config': 'modbus_tcp'});
  logger.info('Channel started successfully', deviceId: 'device1');
  logger.warn('Slow operation detected', 
              deviceId: 'device2', 
              context: {'duration_ms': 150});
  logger.error('Communication error', 
               deviceId: 'device2', 
               error: 'Connection timeout',
               context: {'operation': 'read_holding_registers'});

  // Demonstrate device-specific logging
  print('\nTesting device-specific log levels:');
  
  // This should appear (device1 is set to DEBUG)
  logger.debug('Debug message for device1', deviceId: 'device1');
  
  // This should NOT appear (device2 is set to WARN, debug is below warn)
  logger.debug('Debug message for device2', deviceId: 'device2');
  
  // This should appear (device2 is set to WARN)
  logger.warn('Warning message for device2', deviceId: 'device2');
  
  print('');
}

Future<void> _demonstratePerformanceMonitoring(ServiceManager serviceManager) async {
  print('=== Performance Monitoring Demo ===');
  
  final perfMon = LoggingManager.instance.performanceMonitor;
  
  // Simulate channel operations with performance measurement
  await _simulateChannelOperations(perfMon);
  
  // Display performance statistics
  final stats = serviceManager.getPerformanceStats();
  
  print('\nPerformance Statistics:');
  for (final entry in stats.entries) {
    final deviceId = entry.key;
    final deviceStats = entry.value;
    
    print('\nDevice: $deviceId');
    print('  Total Operations: ${deviceStats.totalOperations}');
    print('  Success Rate: ${(deviceStats.successRate * 100).toStringAsFixed(1)}%');
    print('  Average Duration: ${deviceStats.averageDuration.inMilliseconds}ms');
    print('  Operations/sec: ${deviceStats.operationsPerSecond.toStringAsFixed(2)}');
    
    // Show operation-specific stats
    for (final opEntry in deviceStats.operationStats.entries) {
      final opType = opEntry.key;
      final opStats = opEntry.value;
      print('  $opType: ${opStats.count} ops, '
            '${opStats.averageDuration.inMilliseconds}ms avg, '
            '${(opStats.successRate * 100).toStringAsFixed(1)}% success');
    }
  }
  
  // Display recent metrics
  print('\nRecent Poll Metrics:');
  final recentMetrics = perfMon.getRecentMetrics('device1', limit: 5);
  for (final metric in recentMetrics) {
    print('  ${metric.operationType}: ${metric.duration.inMilliseconds}ms '
          '(${metric.success ? 'SUCCESS' : 'FAILED'})');
  }
}

Future<void> _simulateChannelOperations(PerformanceMonitor perfMon) async {
  print('Simulating channel operations...');
  
  // Simulate multiple poll cycles
  for (int cycle = 0; cycle < 5; cycle++) {
    final pollCycleId = 'cycle_$cycle';
    
    // Simulate a poll cycle
    final pollTimer = perfMon.startPollTimer('device1', pollCycleId: pollCycleId);
    
    // Simulate poll units within the cycle
    for (int unit = 0; unit < 3; unit++) {
      final pollUnitTimer = perfMon.startPollUnitTimer(
        'device1', 
        unit, 
        pollCycleId: pollCycleId
      );
      
      // Simulate processing time
      await Future.delayed(Duration(milliseconds: 10 + unit * 5));
      
      // Randomly succeed or fail
      if (DateTime.now().millisecond % 10 == 0) {
        pollUnitTimer.fail();
      } else {
        pollUnitTimer.complete();
      }
    }
    
    pollTimer.complete();
    
    // Simulate write operations
    if (cycle % 2 == 0) {
      final writeTimer = perfMon.startWriteTimer('device1', 
          details: {'tag': 'output_register', 'value': cycle});
      
      await Future.delayed(Duration(milliseconds: 15));
      writeTimer.complete();
    }
  }
  
  // Simulate some operations for device2
  for (int i = 0; i < 3; i++) {
    final pollTimer = perfMon.startPollTimer('device2');
    await Future.delayed(Duration(milliseconds: 20));
    
    // Simulate occasional failures
    if (i == 1) {
      pollTimer.fail();
    } else {
      pollTimer.complete();
    }
  }
}