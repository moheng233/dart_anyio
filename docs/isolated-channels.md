# Isolated Channel Architecture

## Overview

The Isolated Channel Architecture provides fault-tolerant channel communication by running each channel in a separate Dart isolate. This design ensures that if one channel crashes, it doesn't affect other channels or the main service.

## Features

### ✅ Channel Isolation
- Each channel runs in its own Dart isolate
- Crashes in one channel don't affect others
- Memory and execution isolation between channels

### ✅ Automatic Crash Detection
- Monitors isolate health and exit events
- Detects communication failures
- Handles unexpected isolate termination

### ✅ Automatic Restart
- Configurable restart attempts (default: 3)
- Configurable restart delay (default: 5 seconds)
- Exponential backoff for repeated failures
- Reset restart counter on successful operation

### ✅ Inter-Isolate Communication
- JSON-based message serialization
- Bidirectional communication between main service and channels
- Event forwarding (device events → channel, channel events → service)
- Error reporting from isolated channels

## Architecture

```
Main Isolate                    Channel Isolate
┌─────────────────┐            ┌──────────────────┐
│  ServiceManager │            │ IsolatedChannel  │
│  ┌────────────┐ │            │  Worker          │
│  │   Device   │ │◄────────┐  │                  │
│  │            │ │         │  │ ┌──────────────┐ │
│  └────────────┘ │         │  │ │ Actual       │ │
│                 │         │  │ │ Channel      │ │
│ ┌─────────────┐ │         │  │ │ Session      │ │
│ │ Isolated    │ │◄────────┼─►│ │              │ │
│ │ Channel     │ │         │  │ └──────────────┘ │
│ │ Session     │ │         │  │                  │
│ └─────────────┘ │         │  │ ┌──────────────┐ │
│                 │         │  │ │   Transport  │ │
│ ┌─────────────┐ │         │  │ │   Session    │ │
│ │ Channel     │ │         │  │ └──────────────┘ │
│ │ Manager     │ │◄────────┘  └──────────────────┘
│ └─────────────┘ │
└─────────────────┘
```

## Usage

### Basic Setup

```dart
// Create channel manager with isolation enabled
final channelManager = ChannelManagerImpl(useIsolatedChannels: true);

// Create service manager with restart settings
final serviceManager = ServiceManager(
  channelManager: channelManager,
  transportManager: transportManager,
  enableChannelRestart: true,    // Enable auto-restart
  maxRestartAttempts: 3,         // Max restart attempts
  restartDelaySeconds: 5,        // Delay between restarts
);
```

### Monitoring Channel Health

```dart
// Get restart statistics
final stats = serviceManager.getRestartStats();
print('Channel restart attempts: $stats');

// Manual channel restart
final success = await serviceManager.restartChannel('device-id');
if (success) {
  print('Channel restarted successfully');
}
```

## Configuration Options

### ChannelManagerImpl Parameters

- `useIsolatedChannels`: Enable/disable isolation (default: true)

### ServiceManager Parameters

- `enableChannelRestart`: Enable automatic restart on failures (default: true)
- `maxRestartAttempts`: Maximum restart attempts per channel (default: 3)
- `restartDelaySeconds`: Delay between restart attempts (default: 5)

## Error Handling

### Types of Errors Handled

1. **Isolate Crashes**: Unexpected isolate termination
2. **Communication Failures**: SendPort/ReceivePort errors
3. **Channel Exceptions**: Errors within channel logic
4. **Timeout Errors**: Communication timeouts

### Restart Logic

1. Detect error or isolate exit
2. Check if max restart attempts reached
3. Wait for configured delay
4. Clean up old isolate resources
5. Create new isolate and initialize channel
6. Resume normal operation

### Error Recovery

```dart
// Automatic error recovery flow
Channel Error/Crash
        ↓
    Log Error
        ↓
Check Restart Attempts < Max
        ↓
    Wait Delay
        ↓
  Cleanup Old Isolate
        ↓
 Create New Isolate
        ↓
Initialize Channel
        ↓
   Resume Operation
```

## Inter-Isolate Communication Protocol

### Message Types

1. **InitChannelMessage**: Initialize channel in isolate
2. **StartChannelMessage**: Start channel operations
3. **StopChannelMessage**: Stop channel operations
4. **DeviceEventMessage**: Forward device events to channel
5. **ChannelEventMessage**: Forward channel events to main service
6. **ChannelErrorMessage**: Report errors from channel

### Message Serialization

All complex objects are serialized to JSON for inter-isolate communication:

```dart
// Device event serialization
{
  'json': {'deviceId': 'device1', 'tagId': 'temp', 'value': 25.5},
  'type': 'DeviceWriteEvent'
}

// Channel event serialization
{
  'json': {'deviceId': 'device1', 'updates': [...]},
  'type': 'ChannelUpdateEvent'
}
```

## Benefits

### 🛡️ Fault Tolerance
- Single channel failures don't affect the entire system
- Automatic recovery from channel crashes
- Improved system reliability

### 🔒 Isolation
- Memory isolation prevents memory leaks in one channel affecting others
- Execution isolation prevents blocking operations in one channel affecting others
- Security isolation between different device communications

### 📊 Monitoring
- Built-in restart statistics
- Error tracking per channel
- Health monitoring capabilities

### 🔧 Maintainability
- Clean separation of channel logic
- Easier debugging of channel-specific issues
- Independent channel lifecycle management

## Limitations

### Performance Overhead
- Inter-isolate communication has serialization costs
- Memory overhead for multiple isolates
- Slightly higher latency compared to in-process channels

### Complexity
- More complex error handling
- Additional debugging complexity
- Requires understanding of Dart isolate model

## Migration from Non-Isolated Channels

Existing code can be migrated by simply changing the channel manager configuration:

```dart
// Before (non-isolated)
final channelManager = ChannelManagerImpl();

// After (isolated)
final channelManager = ChannelManagerImpl(useIsolatedChannels: true);
```

The API remains the same, making migration seamless.

## Future Enhancements

- **Resource Limits**: CPU and memory limits per isolate
- **Health Checks**: Periodic health checks for channels
- **Load Balancing**: Distribute channels across multiple isolate pools
- **Metrics**: Detailed performance and error metrics
- **Configuration Hot-Reload**: Dynamic reconfiguration without restart