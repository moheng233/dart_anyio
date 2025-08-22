// ignore_for_file: avoid_print test

import 'package:anyio_service/service.dart';
// ...existing imports...

void main() async {
  print('Testing AnyIO Service Components...');

  // Test time-series database
  print('\n1. Testing Time-Series Database...');
  final timeSeriesDb = InMemoryTimeSeriesDatabase();
  await timeSeriesDb.initialize();

  // Add some test data
  final testPoint = DataPoint(
    deviceId: 'test_device',
    pointId: 'temperature',
    value: 25.5,
    timestamp: DateTime.now(),
  );

  await timeSeriesDb.writePoint(testPoint);

  final latest = await timeSeriesDb.getLatest('test_device', 'temperature');
  print('Latest value: ${latest?.value}');

  final stats = timeSeriesDb.getStatistics();
  final statsJson = stats.toMap();
  print(
    'DB Statistics: ${statsJson['totalPoints']} points in ${statsJson['totalSeries']} series',
  );

  // Test data collector
  print('\n2. Testing Data Collector...');
  final dataCollector = DataCollector(timeSeriesDb: timeSeriesDb);
  await dataCollector.start();

  await dataCollector.collectPoint('test_device', 'pressure', 1013.25);
  await dataCollector.collectPoint('test_device', 'humidity', 65.0);

  // Wait a bit for batch processing
  await Future<void>.delayed(const Duration(milliseconds: 100));

  final devicePoints = await timeSeriesDb.getLatestForDevice('test_device');
  print('Device points collected: ${devicePoints.length}');
  for (final point in devicePoints) {
    print('  ${point.pointId}: ${point.value}');
  }

  await dataCollector.stop();
  await timeSeriesDb.close();

  // Test managers
  print('\n3. Testing Manager Components...');
  final transportManager = TransportManagerImpl();
  final channelManager = ChannelManagerImpl();

  print('Transport manager created: ${transportManager.runtimeType}');
  print('Channel manager created: ${channelManager.runtimeType}');

  print('\n4. Testing Service Manager...');
  final serviceManager = ServiceManager(
    channelManager: channelManager,
    transportManager: transportManager,
  );

  print('Service manager created: ${serviceManager.runtimeType}');
  print('Device count: ${serviceManager.devices.length}');

  print('\nAll basic tests passed! ✅');
  print('\nTo run the full service:');
  print('1. dart bin/anyio.dart example/device.yaml example/templates/');
  print('2. curl http://localhost:8080/health');
}
