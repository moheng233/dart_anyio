import 'dart:async';

import 'package:anyio_template/service.dart';

import '../database.dart';
import 'questdb_client.dart';
import 'questdb_sender.dart';

final class RecordDatabaseQuestDBImpl extends RecordDatabase {
  RecordDatabaseQuestDBImpl({
    required this.api,
    required this.sender,
    required this.variableDefinitions,
    required this.actionDefinitions,
  });

  static Future<RecordDatabaseQuestDBImpl> create({
    required String serverIp,
    required Map<String, Map<String, VariableInfo>> variableDefinitions,
    required Map<String, Map<String, ActionInfo>> actionDefinitions,
    int apiPort = 9000,
    String? username,
    String? password,
    String? token,
    bool isHttps = false,
  }) async {
    final api = QuestDbApi(
      host: serverIp,
      port: apiPort,
      username: username,
      password: password,
      token: token,
      isHttps: isHttps,
    );

    final sender = await QuestDbSender.fromOptions(
      SenderOptions(
        host: serverIp,
        port: apiPort, // QuestDB unified port
        username: username,
        password: password,
        token: token,
        isHttps: isHttps,
      ),
    );

    return RecordDatabaseQuestDBImpl(
      api: api,
      sender: sender,
      variableDefinitions: variableDefinitions,
      actionDefinitions: actionDefinitions,
    );
  }

  final QuestDbApi api;
  final QuestDbSender sender;
  final Map<String, Map<String, VariableInfo>> variableDefinitions;
  final Map<String, Map<String, ActionInfo>> actionDefinitions;

  @override
  FutureOr<void> addPerformanceCountEvent(String eventName, int count) async {
    await sender.add('performance_counts', (b) {
      b
        ..tag('event_type', 'count')
        ..tag('event_name', eventName)
        ..longColumn('count', count)
        ..at(DateTime.now().toUtc());
    });
  }

  @override
  FutureOr<void> addPerformanceRangeEvent(
    String eventName,
    DateTime startTime,
    DateTime endTime,
  ) async {
    await sender.add('performance_ranges', (b) {
      b
        ..tag('event_type', 'range')
        ..tag('event_name', eventName)
        ..longColumn('start_time', startTime.millisecondsSinceEpoch)
        ..longColumn('end_time', endTime.millisecondsSinceEpoch)
        ..longColumn('duration_ms', endTime.difference(startTime).inMilliseconds)
        ..at(DateTime.now().toUtc());
    });
  }

  @override
  FutureOr<void> addRecord(
    String name,
    DateTime time,
    Map<String, Object?> values,
  ) async {
    await sender.add(name, (b) {
      b.at(time.toUtc());
      
      // Add all fields from values map
      for (final entry in values.entries) {
        final column = entry.key;
        final value = entry.value;
        
        if (value is String) {
          b.stringColumn(column, value);
        } else if (value is int) {
          b.longColumn(column, value);
        } else if (value is double) {
          b.floatColumn(column, value);
        } else if (value is bool) {
          b.boolColumn(column, value);
        } else if (value is DateTime) {
          b.timestampColumn(column, value);
        } else if (value is List) {
          b.arrayColumn(column, value);
        } else {
          // For other types, convert to string
          b.stringColumn(column, value?.toString() ?? '');
        }
      }
    });
  }

  @override
  FutureOr<bool> initialize() async {
    try {
      // Check if performance_counts table exists
      final countTableExists = await _tableExists('performance_counts');
      if (!countTableExists) {
        await _createPerformanceCountsTable();
      }

      // Check if performance_ranges table exists
      final rangeTableExists = await _tableExists('performance_ranges');
      if (!rangeTableExists) {
        await _createPerformanceRangesTable();
      }

      return true;
    } on Exception {
      return false;
    }
  }

  /// Check if a table exists
  Future<bool> _tableExists(String tableName) async {
    try {
      final result = await api.exec(
        'SELECT 1 FROM information_schema.tables '
        "WHERE table_name = '$tableName' LIMIT 1",
      );
      return result is List && result.isNotEmpty;
    } on Exception {
      // If query fails, assume table doesn't exist
      return false;
    }
  }

  /// Create performance_counts table
  Future<void> _createPerformanceCountsTable() async {
    const createTableQuery = '''
      CREATE TABLE performance_counts (
        timestamp TIMESTAMP,
        event_name STRING,
        count LONG,
        event_type STRING
      ) TIMESTAMP(timestamp) PARTITION BY DAY;
    ''';
    await api.exec(createTableQuery);
  }

  /// Create performance_ranges table
  Future<void> _createPerformanceRangesTable() async {
    const createTableQuery = '''
      CREATE TABLE performance_ranges (
        timestamp TIMESTAMP,
        event_name STRING,
        start_time LONG,
        end_time LONG,
        duration_ms LONG,
        event_type STRING
      ) TIMESTAMP(timestamp) PARTITION BY DAY;
    ''';
    await api.exec(createTableQuery);
  }
}
