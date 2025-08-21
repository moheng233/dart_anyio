# Logging and Performance Monitoring

## Overview

The AnyIO Service includes a comprehensive logging and performance monitoring system that provides device-specific logging levels, detailed channel operation tracking, and real-time performance metrics.

## Features

### ✅ Device-Specific Logging
- Configure log levels per device ID
- Global default log level
- Multiple log outputs (console, file, custom)
- Structured logging with context and metadata

### ✅ Performance Monitoring
- Poll cycle timing measurement
- Individual poll unit timing within cycles
- Write operation performance tracking
- Channel startup/shutdown/restart timing
- Success/failure rate tracking

### ✅ Channel Operation Logging
- Channel startup and shutdown events
- Error detection and restart attempts
- Inter-isolate communication logging
- Transport and communication errors

## Logging System

### Log Levels

```dart
enum LogLevel {
  trace,   // Detailed debug information
  debug,   // Debug information  
  info,    // General information
  warn,    // Warning messages
  error,   // Error messages
  fatal,   // Critical errors
}
```

### Logger Types

#### Console Logger
Outputs to stdout/stderr with color coding:

```dart
final logger = ConsoleLogger(globalLevel: LogLevel.info);
```

#### File Logger
Outputs to file with automatic rotation:

```dart
final logger = FileLogger(
  logFilePath: 'logs/service.log',
  globalLevel: LogLevel.debug,
  maxFileSizeBytes: 10 * 1024 * 1024, // 10MB
  maxBackupFiles: 5,
);
```

#### Multi Logger
Forwards to multiple logger implementations:

```dart
final logger = MultiLogger([
  ConsoleLogger(globalLevel: LogLevel.info),
  FileLogger(logFilePath: 'logs/service.log'),
]);
```

### Device-Specific Log Levels

Configure different log levels for different devices:

```dart
// Set global default
serviceManager.setGlobalLogLevel(LogLevel.info);

// Override for specific devices
serviceManager.setDeviceLogLevel('critical-device', LogLevel.debug);
serviceManager.setDeviceLogLevel('stable-device', LogLevel.warn);
```

### Structured Logging

All log messages support structured data:

```dart
logger.info('Channel started', 
           deviceId: 'device1',
           context: {
             'transport': 'TCP',
             'address': '192.168.1.100',
             'port': 502,
           });

logger.error('Communication failed',
            deviceId: 'device1',
            error: exception,
            stackTrace: stackTrace,
            context: {'operation': 'read_holding_registers'});
```

## Performance Monitoring

### Performance Metrics

The system tracks various operation types:

```dart
enum PerformanceOperationType {
  poll,      // Complete poll cycle
  pollUnit,  // Individual poll unit within cycle
  write,     // Write operations
  startup,   // Channel startup
  shutdown,  // Channel shutdown  
  restart,   // Channel restart
}
```

### Using Performance Timers

#### Manual Timing

```dart
final perfMon = LoggingManager.instance.performanceMonitor;

// Start a timer
final timer = perfMon.startPollTimer('device1', pollCycleId: 'cycle_123');

// Do work...

// Complete successfully
timer.complete();

// Or mark as failed
// timer.fail();
```

#### Automatic Timing in Isolated Channels

The isolated channel implementation automatically measures:

- **Poll Cycles**: Complete polling operations
- **Poll Units**: Individual units within a poll cycle
- **Write Operations**: Device write commands
- **Channel Lifecycle**: Startup, shutdown, restart operations

### Performance Statistics

#### Real-time Statistics

```dart
// Get stats for all devices
final allStats = serviceManager.getPerformanceStats();

// Get stats for specific device
final deviceStats = serviceManager.getDevicePerformanceStats('device1');

print('Success Rate: ${(deviceStats.successRate * 100).toStringAsFixed(1)}%');
print('Average Duration: ${deviceStats.averageDuration.inMilliseconds}ms');
print('Operations/sec: ${deviceStats.operationsPerSecond.toStringAsFixed(2)}');
```

#### Operation-Specific Statistics

```dart
final pollStats = deviceStats.getOperationStats(PerformanceOperationType.poll);
if (pollStats != null) {
  print('Poll Operations: ${pollStats.count}');
  print('Poll Success Rate: ${(pollStats.successRate * 100).toStringAsFixed(1)}%');
  print('Average Poll Time: ${pollStats.averageDuration.inMilliseconds}ms');
}
```

#### Recent Metrics

```dart
final recentMetrics = perfMon.getRecentMetrics('device1', limit: 10);
for (final metric in recentMetrics) {
  print('${metric.operationType}: ${metric.duration.inMilliseconds}ms '
        '${metric.success ? "SUCCESS" : "FAILED"}');
}
```

## Service Manager Integration

### Initialization

```dart
final serviceManager = ServiceManager(
  channelManager: ChannelManagerImpl(useIsolatedChannels: true),
  transportManager: transportManager,
  logger: MultiLogger([
    ConsoleLogger(globalLevel: LogLevel.info),
    FileLogger(logFilePath: 'logs/service.log'),
  ]),
  performanceMonitor: PerformanceMonitor(maxHistorySize: 1000),
  performanceThresholds: {
    PerformanceOperationType.poll: Duration(milliseconds: 100),
    PerformanceOperationType.write: Duration(milliseconds: 50),
  },
);
```

### Log Management

```dart
// Configure logging
serviceManager.setGlobalLogLevel(LogLevel.info);
serviceManager.setDeviceLogLevel('device1', LogLevel.debug);

// Clear performance data
serviceManager.clearDevicePerformanceMetrics('device1');
```

## Isolated Channel Integration

### Automatic Logging

Isolated channels automatically log:

- Isolate creation and initialization
- Channel startup/shutdown events
- Communication errors and recovery
- Performance metrics forwarding

### Performance Measurement

Each isolated channel worker measures:

- **Poll Cycles**: Full polling operations with cycle IDs
- **Poll Units**: Individual units within each cycle
- **Write Operations**: Device write commands
- **Error Recovery**: Restart and recovery operations

### Log Output Example

```
2024-01-15T10:30:15.123Z [INFO ] [device1] Opening isolated channel
2024-01-15T10:30:15.145Z [DEBUG] [device1] Creating isolate for channel
2024-01-15T10:30:15.234Z [INFO ] [device1] Isolate created successfully
2024-01-15T10:30:15.235Z [DEBUG] [device1] Isolate ready, initializing channel
2024-01-15T10:30:15.236Z [INFO ] [device1] Channel initialization sent
2024-01-15T10:30:16.001Z [TRACE] [device1] Starting poll cycle | Context: {"poll_cycle_id": "cycle_0"}
2024-01-15T10:30:16.015Z [TRACE] [device1] Poll unit completed | Context: {"poll_cycle_id": "cycle_0", "poll_unit_index": 0}
2024-01-15T10:30:16.025Z [TRACE] [device1] Poll unit completed | Context: {"poll_cycle_id": "cycle_0", "poll_unit_index": 1}
2024-01-15T10:30:16.040Z [TRACE] [device1] Poll unit completed | Context: {"poll_cycle_id": "cycle_0", "poll_unit_index": 2}
2024-01-15T10:30:16.041Z [TRACE] [device1] Poll cycle completed | Context: {"poll_cycle_id": "cycle_0"}
```

## Performance Thresholds

Configure performance warning thresholds:

```dart
final serviceManager = ServiceManager(
  // ... other parameters
  performanceThresholds: {
    PerformanceOperationType.poll: Duration(milliseconds: 100),
    PerformanceOperationType.pollUnit: Duration(milliseconds: 25),
    PerformanceOperationType.write: Duration(milliseconds: 50),
    PerformanceOperationType.startup: Duration(seconds: 10),
  },
);
```

When operations exceed thresholds, warnings are automatically logged.

## Best Practices

### Logging

1. **Use appropriate log levels**:
   - `TRACE`: Very detailed debugging (poll unit details)
   - `DEBUG`: General debugging (channel events, configuration)
   - `INFO`: Important events (startup, shutdown, significant operations)
   - `WARN`: Concerning but non-critical issues (slow operations, retries)
   - `ERROR`: Errors that affect functionality
   - `FATAL`: Critical system failures

2. **Include context**: Always provide relevant context in log messages

3. **Device-specific levels**: Use device-specific log levels for granular control

4. **Structured logging**: Use the context parameter for machine-readable data

### Performance Monitoring

1. **Monitor key metrics**:
   - Poll cycle times
   - Success rates
   - Operations per second
   - Error frequency

2. **Set appropriate thresholds**: Configure warnings for slow operations

3. **Regular cleanup**: Clear old performance data for memory management

4. **Trend analysis**: Monitor performance trends over time

## Integration with Existing Code

The logging and performance monitoring systems integrate seamlessly with existing AnyIO service code:

```dart
// Minimal configuration
final serviceManager = ServiceManager(
  channelManager: ChannelManagerImpl(useIsolatedChannels: true),
  transportManager: transportManager,
  // Logging and performance monitoring are automatically initialized
);

// Access logging and performance monitoring
final logger = LoggingManager.instance.logger;
final perfMon = LoggingManager.instance.performanceMonitor;
```

## Example Usage

See `example/logging_demo.dart` for a complete demonstration of logging and performance monitoring features.

## File Log Rotation

File logs automatically rotate when they reach the configured size:

- Current log: `service.log`
- Rotated logs: `service.log.1`, `service.log.2`, etc.
- Configurable number of backup files
- Automatic cleanup of old backup files

## Memory Management

- Performance metrics have configurable history limits
- Automatic cleanup of old metrics in isolated channels
- Log file rotation prevents disk space issues
- Streaming log output avoids memory accumulation