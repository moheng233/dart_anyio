# AnyIO Service Gateway

The AnyIO Service Gateway is a complete implementation of a data collection and management service that provides:

1. **Service Configuration Management** - Load and manage device configurations from YAML files
2. **Device Template System** - Support for modular device templates with point definitions
3. **Channel Management** - Start and manage communication channels (currently supports Modbus)
4. **Data Collection Pipeline** - Automatic collection of device data and forwarding to storage
5. **Time-Series Database Interface** - Store and query historical point data
6. **HTTP API** - RESTful interface for external systems to access device data

## Features

### Service Management
- **Configuration Loading**: YAML-based device and template configuration
- **Device Lifecycle**: Automatic device initialization, data collection, and cleanup
- **Transport Abstraction**: Support for multiple transport types (TCP, etc.)
- **Channel Abstraction**: Support for multiple protocol adapters (Modbus, etc.)

### Data Collection
- **Real-time Data**: Automatic collection from device channels
- **Time-Series Storage**: Configurable storage backend with query capabilities
- **Data Quality**: Support for data quality indicators
- **Batching**: Efficient batch writing to reduce database load

### HTTP API
The service provides a comprehensive REST API:

#### Device Management
- `GET /devices` - List all configured devices
- `GET /devices/{deviceId}` - Get device details and current values
- `GET /devices/{deviceId}/values` - Get all current values for a device
- `GET /devices/{deviceId}/points` - Get point definitions for a device
- `GET /devices/{deviceId}/points/{pointId}` - Get specific point value

#### Device Control
- `POST /devices/{deviceId}/write` - Write value to a device point
  ```json
  {
    "pointId": "point_name",
    "value": 123
  }
  ```

#### Historical Data
- `GET /history/{deviceId}[/{pointId}]` - Query historical data
  - Query parameters:
    - `start`: ISO8601 timestamp for start time
    - `end`: ISO8601 timestamp for end time
    - `limit`: Maximum number of points to return (default: 1000)

#### System Status
- `GET /health` - Health check endpoint
- `GET /stats` - System statistics and storage information

## Configuration

### Device Configuration (device.yaml)
```yaml
devices:
  - name: "device1"
    template: "modbus_device"
    channel:
      type: "modbus"
      isRtu: true
      unitId: 1
    transportOption:
      type: "tcp"
      host: "192.168.1.100"
      port: 502
```

### Device Template (templates/modbus_device.yaml)
```yaml
info:
  name: modbus_device
  version: "1.0"
meta: {}
points:
  temperature: { type: value, displayName: "Temperature" }
  status: { type: enum, access: rw, values: { "Off": 0, "On": 1 } }
template:
  type: modbus
  polls:
    - begin: 0
      length: 2
      function: 3
      interval_ms: 1000
      mapping:
        - { to: temperature, offset: 0, length: 1, type: float }
        - { to: status, offset: 1, length: 1, type: uint }
```

## Usage

### Running the Service

```bash
# Basic usage
dart bin/anyio.dart device.yaml templates/

# With custom HTTP port
dart bin/anyio.dart device.yaml templates/ 9090

# Using the example script
./run_example.sh
```

### Example API Usage

```bash
# Get all devices
curl http://localhost:8080/devices

# Get device details
curl http://localhost:8080/devices/device1

# Get current values
curl http://localhost:8080/devices/device1/values

# Write to a device
curl -X POST http://localhost:8080/devices/device1/write \
  -H "Content-Type: application/json" \
  -d '{"pointId": "status", "value": 1}'

# Query historical data
curl "http://localhost:8080/history/device1/temperature?start=2024-01-01T00:00:00Z&limit=100"
```

## Architecture

The service follows a modular architecture:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   HTTP API      │    │  Service Mgr    │    │ Time Series DB  │
│                 │    │                 │    │                 │
│ - REST endpoints│    │ - Config mgmt   │    │ - Data storage  │
│ - Device access │    │ - Device mgmt   │    │ - Query engine  │
│ - History query │    │ - Lifecycle     │    │ - Statistics    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────┬───────────┴───────────┬───────────┘
                     │                       │
┌─────────────────────────────────┐    ┌─────────────────┐
│        Device Layer             │    │ Data Collector  │
│                                 │    │                 │
│ ┌─────────┐ ┌─────────┐        │    │ - Event listen  │
│ │Device 1 │ │Device 2 │  ...   │    │ - Batch write   │
│ └─────────┘ └─────────┘        │    │ - Quality mgmt  │
└─────────────────────────────────┘    └─────────────────┘
         │                 │
         │                 │
┌─────────────────┐ ┌─────────────────┐
│   Channel 1     │ │   Channel 2     │
│                 │ │                 │
│ - Protocol impl │ │ - Protocol impl │
│ - Data polling  │ │ - Data polling  │
│ - Transport     │ │ - Transport     │
└─────────────────┘ └─────────────────┘
```

## Extending the Service

### Adding New Protocols
1. Implement `ChannelFactoryBase` for your protocol
2. Implement `ChannelSessionBase` with protocol-specific logic
3. Register the factory with the channel manager

### Adding New Transport Types
1. Implement `TransportFactoryBase` for your transport
2. Implement `TransportSessionBase` with transport-specific logic  
3. Register the factory with the transport manager

### Custom Time-Series Backends
1. Implement the `TimeSeriesDatabase` interface
2. Replace `InMemoryTimeSeriesDatabase` in the main service

## Dependencies

- `dart_mappable`: For configuration serialization/deserialization
- `checked_yaml`: For safe YAML parsing
- `anyio_template`: Core template and event system
- `anyio_adapter_modbus`: Modbus protocol implementation

## Development

The service includes comprehensive error handling, graceful shutdown, and extensible architecture to support additional protocols and features as needed.