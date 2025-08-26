/// Performance measurement and monitoring system for channels
class PerformanceMonitor {
  PerformanceMonitor({this.maxHistorySize = 1000});

  final int maxHistorySize;
  final Map<String, List<PerformanceMetric>> _deviceMetrics = {};
  final Map<String, ChannelPerformanceStats> _deviceStats = {};

  /// Record a performance metric for a device
  void recordMetric(PerformanceMetric metric) {
    final deviceId = metric.deviceId;

    // Add to history
    _deviceMetrics.putIfAbsent(deviceId, () => <PerformanceMetric>[]);
    final metrics = _deviceMetrics[deviceId]!..add(metric);

    // Maintain history size limit
    if (metrics.length > maxHistorySize) {
      metrics.removeAt(0);
    }

    // Update statistics
    _updateStats(deviceId, metric);
  }

  /// Get current performance statistics for a device
  ChannelPerformanceStats? getStats(String deviceId) {
    return _deviceStats[deviceId];
  }

  /// Get all device performance statistics
  Map<String, ChannelPerformanceStats> getAllStats() {
    return Map.unmodifiable(_deviceStats);
  }

  /// Get recent metrics for a device
  List<PerformanceMetric> getRecentMetrics(String deviceId, {int? limit}) {
    final metrics = _deviceMetrics[deviceId] ?? [];
    if (limit == null) return List.unmodifiable(metrics);

    final startIndex = metrics.length > limit ? metrics.length - limit : 0;
    return List.unmodifiable(metrics.sublist(startIndex));
  }

  /// Clear metrics for a device
  void clearDeviceMetrics(String deviceId) {
    _deviceMetrics.remove(deviceId);
    _deviceStats.remove(deviceId);
  }

  /// Clear all metrics
  void clearAllMetrics() {
    _deviceMetrics.clear();
    _deviceStats.clear();
  }

  void _updateStats(String deviceId, PerformanceMetric metric) {
    _deviceStats
        .putIfAbsent(
          deviceId,
          () => ChannelPerformanceStats(deviceId: deviceId),
        )
        ._updateWith(metric);
  }
}

/// Types of performance operations
enum PerformanceOperationType {
  poll,
  pollUnit,
  write,
  startup,
  shutdown,
  restart,
}

/// Individual performance metric
class PerformanceMetric {
  PerformanceMetric({
    required this.deviceId,
    required this.operationType,
    required this.duration,
    required this.timestamp,
    this.success = true,
    this.details,
    this.pollUnitIndex,
    this.pollCycleId,
  });

  final String deviceId;
  final PerformanceOperationType operationType;
  final Duration duration;
  final DateTime timestamp;
  final bool success;
  final Map<String, dynamic>? details;

  /// For poll unit operations, which unit in the cycle
  final int? pollUnitIndex;

  /// For poll operations, unique cycle identifier
  final String? pollCycleId;

  @override
  String toString() {
    return 'PerformanceMetric(deviceId: $deviceId, operation: $operationType, '
        'duration: ${duration.inMilliseconds}ms, success: $success)';
  }
}

/// Aggregated performance statistics for a channel
class ChannelPerformanceStats {
  ChannelPerformanceStats({required this.deviceId});

  final String deviceId;

  int _totalOperations = 0;
  int _successfulOperations = 0;
  int _failedOperations = 0;

  Duration _totalDuration = Duration.zero;
  Duration _minDuration = const Duration(days: 1);
  Duration _maxDuration = Duration.zero;

  final Map<PerformanceOperationType, OperationStats> _operationStats = {};

  DateTime? _firstMetric;
  DateTime? _lastMetric;

  /// Total number of operations recorded
  int get totalOperations => _totalOperations;

  /// Number of successful operations
  int get successfulOperations => _successfulOperations;

  /// Number of failed operations
  int get failedOperations => _failedOperations;

  /// Success rate (0.0 to 1.0)
  double get successRate =>
      _totalOperations > 0 ? _successfulOperations / _totalOperations : 0.0;

  /// Average operation duration
  Duration get averageDuration => _totalOperations > 0
      ? Duration(
          microseconds: _totalDuration.inMicroseconds ~/ _totalOperations,
        )
      : Duration.zero;

  /// Minimum operation duration
  Duration get minDuration =>
      _minDuration == const Duration(days: 1) ? Duration.zero : _minDuration;

  /// Maximum operation duration
  Duration get maxDuration => _maxDuration;

  /// First metric timestamp
  DateTime? get firstMetric => _firstMetric;

  /// Last metric timestamp
  DateTime? get lastMetric => _lastMetric;

  /// Operations per second
  double get operationsPerSecond {
    if (_firstMetric == null || _lastMetric == null || _totalOperations == 0) {
      return 0;
    }

    final duration = _lastMetric!.difference(_firstMetric!);
    if (duration.inMilliseconds == 0) return 0;

    return _totalOperations / (duration.inMilliseconds / 1000.0);
  }

  /// Get statistics for a specific operation type
  OperationStats? getOperationStats(PerformanceOperationType type) {
    return _operationStats[type];
  }

  /// Get all operation type statistics
  Map<PerformanceOperationType, OperationStats> get operationStats =>
      Map.unmodifiable(_operationStats);

  void _updateWith(PerformanceMetric metric) {
    _totalOperations++;

    if (metric.success) {
      _successfulOperations++;
    } else {
      _failedOperations++;
    }

    _totalDuration += metric.duration;

    if (metric.duration < _minDuration) {
      _minDuration = metric.duration;
    }

    if (metric.duration > _maxDuration) {
      _maxDuration = metric.duration;
    }

    _firstMetric ??= metric.timestamp;
    _lastMetric = metric.timestamp;

    // Update operation-specific stats

  _operationStats
        .putIfAbsent(
          metric.operationType,
      OperationStats.new,
        )
        ._updateWith(metric);
  }

  @override
  String toString() {
    return 'ChannelPerformanceStats(deviceId: $deviceId, '
        'operations: $_totalOperations, '
        'successRate: ${(successRate * 100).toStringAsFixed(1)}%, '
        'avgDuration: ${averageDuration.inMilliseconds}ms, '
        'opsPerSec: ${operationsPerSecond.toStringAsFixed(1)})';
  }
}

/// Statistics for a specific operation type
class OperationStats {
  int count = 0;
  int successCount = 0;
  int failureCount = 0;
  Duration totalDuration = Duration.zero;
  Duration minDuration = const Duration(days: 1);
  Duration maxDuration = Duration.zero;

  double get successRate => count > 0 ? successCount / count : 0.0;
  Duration get averageDuration => count > 0
      ? Duration(microseconds: totalDuration.inMicroseconds ~/ count)
      : Duration.zero;
  Duration get actualMinDuration =>
      minDuration == const Duration(days: 1) ? Duration.zero : minDuration;

  void _updateWith(PerformanceMetric metric) {
    count++;

    if (metric.success) {
      successCount++;
    } else {
      failureCount++;
    }

    totalDuration += metric.duration;

    if (metric.duration < minDuration) {
      minDuration = metric.duration;
    }

    if (metric.duration > maxDuration) {
      maxDuration = metric.duration;
    }
  }

  @override
  String toString() {
  return 'OperationStats(count: $count, '
        'successRate: ${(successRate * 100).toStringAsFixed(1)}%, '
        'avgDuration: ${averageDuration.inMilliseconds}ms)';
  }
}

/// Helper class for measuring performance with automatic recording
class PerformanceTimer {
  PerformanceTimer({
    required this.deviceId,
    required this.operationType,
    required this.monitor,
    this.pollUnitIndex,
    this.pollCycleId,
    this.details,
  }) : _startTime = DateTime.now();

  final String deviceId;
  final PerformanceOperationType operationType;
  final PerformanceMonitor monitor;
  final int? pollUnitIndex;
  final String? pollCycleId;
  final Map<String, dynamic>? details;

  final DateTime _startTime;
  bool _isRecorded = false;

  /// Complete the timer and record the metric as successful
  void complete({Map<String, dynamic>? additionalDetails}) {
    _record(true, additionalDetails);
  }

  /// Complete the timer and record the metric as failed
  void fail({Map<String, dynamic>? additionalDetails}) {
    _record(false, additionalDetails);
  }

  /// Complete the timer with explicit success/failure
  void finish({
    required bool success,
    Map<String, dynamic>? additionalDetails,
  }) {
    _record(success, additionalDetails);
  }

  void _record(bool success, Map<String, dynamic>? additionalDetails) {
    if (_isRecorded) return;

    final endTime = DateTime.now();
    final duration = endTime.difference(_startTime);

    Map<String, dynamic>? combinedDetails;
    if (details != null || additionalDetails != null) {
      combinedDetails = <String, dynamic>{};
      if (details != null) combinedDetails.addAll(details!);
      if (additionalDetails != null) combinedDetails.addAll(additionalDetails);
    }

    final metric = PerformanceMetric(
      deviceId: deviceId,
      operationType: operationType,
      duration: duration,
      timestamp: _startTime,
      success: success,
      details: combinedDetails,
      pollUnitIndex: pollUnitIndex,
      pollCycleId: pollCycleId,
    );

    monitor.recordMetric(metric);
    _isRecorded = true;
  }
}

/// Extension for easy performance monitoring
extension PerformanceMonitorExtension on PerformanceMonitor {
  /// Create a timer for a poll operation
  PerformanceTimer startPollTimer(String deviceId, {String? pollCycleId}) {
    return PerformanceTimer(
      deviceId: deviceId,
      operationType: PerformanceOperationType.poll,
      monitor: this,
      pollCycleId: pollCycleId,
    );
  }

  /// Create a timer for a poll unit operation
  PerformanceTimer startPollUnitTimer(
    String deviceId,
    int pollUnitIndex, {
    String? pollCycleId,
  }) {
    return PerformanceTimer(
      deviceId: deviceId,
      operationType: PerformanceOperationType.pollUnit,
      monitor: this,
      pollUnitIndex: pollUnitIndex,
      pollCycleId: pollCycleId,
    );
  }

  /// Create a timer for a write operation
  PerformanceTimer startWriteTimer(
    String deviceId, {
    Map<String, dynamic>? details,
  }) {
    return PerformanceTimer(
      deviceId: deviceId,
      operationType: PerformanceOperationType.write,
      monitor: this,
      details: details,
    );
  }

  /// Create a timer for a startup operation
  PerformanceTimer startStartupTimer(String deviceId) {
    return PerformanceTimer(
      deviceId: deviceId,
      operationType: PerformanceOperationType.startup,
      monitor: this,
    );
  }

  /// Create a timer for a shutdown operation
  PerformanceTimer startShutdownTimer(String deviceId) {
    return PerformanceTimer(
      deviceId: deviceId,
      operationType: PerformanceOperationType.shutdown,
      monitor: this,
    );
  }

  /// Create a timer for a restart operation
  PerformanceTimer startRestartTimer(String deviceId) {
    return PerformanceTimer(
      deviceId: deviceId,
      operationType: PerformanceOperationType.restart,
      monitor: this,
    );
  }
}
