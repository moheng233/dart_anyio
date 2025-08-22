# Time-Series Database Documentation

The AnyIO Service includes a comprehensive time-series database interface for storing and querying historical device data.

## Features

### Data Storage
- **Point-based Storage**: Each data point contains device ID, point ID, value, timestamp, and quality
- **Automatic Timestamping**: All points are automatically timestamped on collection
- **Data Quality**: Support for data quality indicators (good, bad, uncertain, stale)
- **Batch Operations**: Efficient batch writing to minimize database load

### Query Capabilities
- **Time Range Queries**: Query data within specific time ranges
- **Point-specific Queries**: Query individual points or all points for a device  
- **Limit Support**: Configurable result limits to manage response size
- **Latest Value Access**: Quick access to most recent values

### Storage Backends

#### In-Memory Database (Development/Testing)
The `InMemoryTimeSeriesDatabase` provides a complete implementation for development and testing:

```dart
final timeSeriesDb = InMemoryTimeSeriesDatabase();
await timeSeriesDb.initialize();

// Write data
await timeSeriesDb.writePoint(DataPoint(
  deviceId: 'device1',
  pointId: 'temperature', 
  value: 25.5,
  timestamp: DateTime.now(),
));

// Query data
final query = HistoryQuery(
  deviceId: 'device1',
  pointId: 'temperature',
  startTime: DateTime.now().subtract(Duration(hours: 1)),
  limit: 100,
);
final points = await timeSeriesDb.queryHistory(query);
```

#### Custom Backends
You can implement custom storage backends by implementing the `TimeSeriesDatabase` interface:

```dart
class CustomTimeSeriesDatabase implements TimeSeriesDatabase {
  @override
  Future<void> writePoint(DataPoint point) async {
    // Your implementation
  }
  
  @override
  Future<List<DataPoint>> queryHistory(HistoryQuery query) async {
    // Your implementation
  }
  
  // ... other methods
}
```

## Data Collector

The `DataCollector` automatically handles data collection from devices:

### Features
- **Automatic Collection**: Listens to device events and stores data points
- **Batch Processing**: Configurable batch size for efficient database writes
- **Periodic Flushing**: Timer-based flushing of pending points
- **Error Handling**: Retry mechanism for failed writes
- **Quality Management**: Automatic quality assignment

### Configuration
```dart
final dataCollector = DataCollector(
  timeSeriesDb: timeSeriesDb,
  batchSize: 100,           // Points per batch
  flushInterval: Duration(seconds: 10), // Flush frequency
);

await dataCollector.start();

// Collect individual points
await dataCollector.collectPoint(
  'device1', 
  'temperature', 
  25.5,
  quality: DataQuality.good
);
```

## API Integration

The time-series database is fully integrated with the HTTP API:

### Historical Data Query
```bash
# Query all points for a device
curl "http://localhost:8080/history/device1"

# Query specific point with time range
curl "http://localhost:8080/history/device1/temperature?start=2024-01-01T00:00:00Z&end=2024-01-01T23:59:59Z&limit=1000"
```

### Response Format
```json
{
  "deviceId": "device1",
  "pointId": "temperature", 
  "query": {
    "startTime": "2024-01-01T00:00:00Z",
    "endTime": "2024-01-01T23:59:59Z",
    "limit": 1000
  },
  "data": [
    {
      "deviceId": "device1",
      "pointId": "temperature",
      "value": 25.5,
      "timestamp": "2024-01-01T12:00:00Z",
      "quality": "good"
    }
  ]
}
```

## Performance Considerations

### In-Memory Database
- **Memory Usage**: Stores configurable number of points per series (default: 10,000)
- **Query Performance**: O(n) for time range queries, O(1) for latest value access
- **Scalability**: Suitable for development, testing, and small deployments

### Production Considerations
For production use, consider implementing backends for:
- **InfluxDB**: Purpose-built time-series database
- **TimescaleDB**: PostgreSQL extension for time-series data
- **Prometheus**: Monitoring and alerting toolkit
- **Custom Solutions**: Database-specific optimizations

## Data Quality Types

```dart
enum DataQuality {
  good,       // Valid, reliable data
  bad,        // Invalid or unreliable data  
  uncertain,  // Data quality uncertain
  stale,      // Data is old/outdated
}
```

Quality indicators help downstream systems make decisions about data validity and processing.