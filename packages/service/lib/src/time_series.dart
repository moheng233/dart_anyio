import 'dart:async';
import 'dart:collection';

import 'package:dart_mappable/dart_mappable.dart';

part 'time_series.mapper.dart';

/// Data point for time-series storage
class DataPoint {
  DataPoint({
    required this.deviceId,
    required this.pointId,
    required this.value,
    required this.timestamp,
    this.quality = DataQuality.good,
  });

  final String deviceId;
  final String pointId;
  final Object? value;
  final DateTime timestamp;
  final DataQuality quality;

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'pointId': pointId,
    'value': value,
    'timestamp': timestamp.toIso8601String(),
    'quality': quality.name,
  };

  factory DataPoint.fromJson(Map<String, dynamic> json) => DataPoint(
    deviceId: json['deviceId'] as String,
    pointId: json['pointId'] as String,
    value: json['value'],
    timestamp: DateTime.parse(json['timestamp'] as String),
    quality: DataQuality.values.firstWhere(
      (q) => q.name == json['quality'],
      orElse: () => DataQuality.good,
    ),
  );
}

/// Data quality enumeration
enum DataQuality {
  good,
  bad,
  uncertain,
  stale,
}

/// Query parameters for historical data
class HistoryQuery {
  HistoryQuery({
    required this.deviceId,
    this.pointId,
    this.startTime,
    this.endTime,
    this.limit = 1000,
  });

  final String deviceId;
  final String? pointId;
  final DateTime? startTime;
  final DateTime? endTime;
  final int limit;
}

/// Abstract interface for time-series database operations
abstract interface class TimeSeriesDatabase {
  /// Write a single data point
  Future<void> writePoint(DataPoint point);

  /// Write multiple data points
  Future<void> writePoints(List<DataPoint> points);

  /// Query historical data
  Future<List<DataPoint>> queryHistory(HistoryQuery query);

  /// Get latest value for a point
  Future<DataPoint?> getLatest(String deviceId, String pointId);

  /// Get latest values for all points of a device
  Future<List<DataPoint>> getLatestForDevice(String deviceId);

  /// Initialize the database
  Future<void> initialize();

  /// Close the database connection
  Future<void> close();
}

/// In-memory implementation of time-series database for development/testing
class InMemoryTimeSeriesDatabase implements TimeSeriesDatabase {
  final _data = HashMap<String, List<DataPoint>>();
  final _maxPointsPerSeries = 10000;

  String _getKey(String deviceId, String pointId) => '$deviceId:$pointId';

  @override
  Future<void> initialize() async {
    // No initialization needed for in-memory storage
  }

  @override
  Future<void> close() async {
    _data.clear();
  }

  @override
  Future<void> writePoint(DataPoint point) async {
    final key = _getKey(point.deviceId, point.pointId);

    _data.putIfAbsent(key, () => <DataPoint>[]).add(point);

    // Keep only the latest N points per series
    final series = _data[key]!;
    if (series.length > _maxPointsPerSeries) {
      series.removeRange(0, series.length - _maxPointsPerSeries);
    }
  }

  @override
  Future<void> writePoints(List<DataPoint> points) async {
    for (final point in points) {
      await writePoint(point);
    }
  }

  @override
  Future<List<DataPoint>> queryHistory(HistoryQuery query) async {
    final results = <DataPoint>[];

    if (query.pointId != null) {
      // Query specific point
      final key = _getKey(query.deviceId, query.pointId!);
      final series = _data[key];
      if (series != null) {
        results.addAll(_filterByTime(series, query.startTime, query.endTime));
      }
    } else {
      // Query all points for device
      for (final entry in _data.entries) {
        if (entry.key.startsWith('${query.deviceId}:')) {
          results.addAll(
            _filterByTime(entry.value, query.startTime, query.endTime),
          );
        }
      }
    }

    // Sort by timestamp
    results.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Apply limit
    if (results.length > query.limit) {
      return results.sublist(results.length - query.limit);
    }

    return results;
  }

  @override
  Future<DataPoint?> getLatest(String deviceId, String pointId) async {
    final key = _getKey(deviceId, pointId);
    final series = _data[key];
    return series?.isNotEmpty ?? false ? series?.last : null;
  }

  @override
  Future<List<DataPoint>> getLatestForDevice(String deviceId) async {
    final results = <DataPoint>[];

    for (final entry in _data.entries) {
      if (entry.key.startsWith('$deviceId:') && entry.value.isNotEmpty) {
        results.add(entry.value.last);
      }
    }

    return results;
  }

  List<DataPoint> _filterByTime(
    List<DataPoint> points,
    DateTime? startTime,
    DateTime? endTime,
  ) {
    var filtered = points.asMap().entries.map((e) => e.value);

    if (startTime != null) {
      filtered = filtered.where(
        (p) =>
            p.timestamp.isAfter(startTime) ||
            p.timestamp.isAtSameMomentAs(startTime),
      );
    }

    if (endTime != null) {
      filtered = filtered.where(
        (p) =>
            p.timestamp.isBefore(endTime) ||
            p.timestamp.isAtSameMomentAs(endTime),
      );
    }

    return filtered.toList();
  }

  /// Get statistics about stored data
  TimeSeriesStatistics getStatistics() {
    final totalSeries = _data.length;
    final totalPoints = _data.values
        .map((s) => s.length)
        .fold<int>(0, (a, b) => a + b);

    final Map<String, DeviceSeriesStats> series = {};

    for (final entry in _data.entries) {
      final parts = entry.key.split(':');
      final deviceId = parts[0];
      final pointId = parts[1];

      series.putIfAbsent(deviceId, () => DeviceSeriesStats(points: {}));

      series[deviceId]!.points[pointId] = PointSeriesStats(
        pointCount: entry.value.length,
        latest: entry.value.isNotEmpty ? entry.value.last : null,
      );
    }

    return TimeSeriesStatistics(
      totalSeries: totalSeries,
      totalPoints: totalPoints,
      series: series,
    );
  }
}

/// Data collector that automatically stores device data to time-series database
class DataCollector {
  DataCollector({
    required this.timeSeriesDb,
    this.batchSize = 100,
    this.flushInterval = const Duration(seconds: 10),
  });

  final TimeSeriesDatabase timeSeriesDb;
  final int batchSize;
  final Duration flushInterval;

  final _pendingPoints = <DataPoint>[];
  Timer? _flushTimer;
  bool _isStarted = false;

  /// Start the data collector
  Future<void> start() async {
    if (_isStarted) return;

    await timeSeriesDb.initialize();
    _startFlushTimer();
    _isStarted = true;
  }

  /// Stop the data collector
  Future<void> stop() async {
    if (!_isStarted) return;

    _flushTimer?.cancel();
    await _flushPendingPoints();
    await timeSeriesDb.close();
    _isStarted = false;
  }

  /// Collect a data point
  Future<void> collectPoint(
    String deviceId,
    String pointId,
    Object? value, {
    DataQuality quality = DataQuality.good,
  }) async {
    final point = DataPoint(
      deviceId: deviceId,
      pointId: pointId,
      value: value,
      timestamp: DateTime.now(),
      quality: quality,
    );

    _pendingPoints.add(point);

    if (_pendingPoints.length >= batchSize) {
      await _flushPendingPoints();
    }
  }

  void _startFlushTimer() {
    _flushTimer = Timer.periodic(flushInterval, (_) async {
      await _flushPendingPoints();
    });
  }

  Future<void> _flushPendingPoints() async {
    if (_pendingPoints.isEmpty) return;

    final pointsToFlush = List<DataPoint>.from(_pendingPoints);
    _pendingPoints.clear();

    try {
      await timeSeriesDb.writePoints(pointsToFlush);
    } catch (e) {
      // On error, add points back to pending (simple retry mechanism)
      _pendingPoints.insertAll(0, pointsToFlush);
      print('Failed to write points to time-series database: $e');
    }
  }
}

/// Statistics model for time-series data
@MappableClass()
class PointSeriesStats with PointSeriesStatsMappable {
  PointSeriesStats({required this.pointCount, this.latest});

  final int pointCount;
  final DataPoint? latest;
}

@MappableClass()
class DeviceSeriesStats with DeviceSeriesStatsMappable {
  DeviceSeriesStats({required this.points});

  final Map<String, PointSeriesStats> points;
}

@MappableClass()
class TimeSeriesStatistics with TimeSeriesStatisticsMappable {
  TimeSeriesStatistics({
    required this.totalSeries,
    required this.totalPoints,
    required this.series,
  });

  final int totalSeries;
  final int totalPoints;
  final Map<String, DeviceSeriesStats> series;
}
