import 'dart:async';

abstract class RecordDatabase {
  FutureOr<bool> initialize();

  FutureOr<void> addRecord(
    String name,
    DateTime time,
    Map<String, Object?> values,
  );

  FutureOr<void> addPerformanceCountEvent(
    String eventName,
    int count,
  );

  FutureOr<void> addPerformanceRangeEvent(
    String eventName,
    DateTime startTime,
    DateTime endTime,
  );
}
