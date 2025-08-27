import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Timestamp unit for QuestDB ingestion
enum TimestampUnit {
  nanoseconds('n'),
  microseconds('u'),
  milliseconds('ms'),
  seconds('s');

  const TimestampUnit(this.value);
  final String value;
}

/// QuestDB Sender configuration options
class SenderOptions {
  const SenderOptions({
    required this.host,
    this.port = 9000,
    this.username,
    this.password,
    this.token,
    this.isHttps = false,
    this.autoFlushRows = 1000,
    this.autoFlushInterval = const Duration(seconds: 1),
    this.bufferSize = 65536,
    this.connectTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(seconds: 30),
  });

  /// Create options from connection string
  /// Format: "http::addr=host:port;username=user;password=pass;token=token"
  factory SenderOptions.fromString(String config) {
    final parts = config.split(';');
    var protocol = 'http';
    var host = 'localhost';
    var port = 9000;
    String? username;
    String? password;
    String? token;

    for (final part in parts) {
      final kv = part.split('=');
      if (kv.length != 2) continue;

      final key = kv[0].trim();
      final value = kv[1].trim();

      switch (key) {
        case 'protocol':
          protocol = value;
        case 'addr':
          final addrParts = value.split(':');
          if (addrParts.length == 2) {
            host = addrParts[0];
            port = int.tryParse(addrParts[1]) ?? 9000;
          } else {
            host = value;
          }
        case 'username':
          username = value;
        case 'password':
          password = value;
        case 'token':
          token = value;
      }
    }

    return SenderOptions(
      host: host,
      port: port,
      username: username,
      password: password,
      token: token,
      isHttps: protocol == 'https',
    );
  }

  /// Server host
  final String host;

  /// Server port
  final int port;

  /// Username for authentication
  final String? username;

  /// Password for authentication
  final String? password;

  /// Bearer token for authentication
  final String? token;

  /// Whether to use HTTPS
  final bool isHttps;

  /// Number of rows to buffer before auto-flush
  final int autoFlushRows;

  /// Time interval for auto-flush
  final Duration autoFlushInterval;

  /// Buffer size in bytes
  final int bufferSize;

  /// Connection timeout
  final Duration connectTimeout;

  /// Receive timeout
  final Duration receiveTimeout;
}

/// QuestDB data sender with fluent API
class QuestDbSender {
  QuestDbSender._(this._options, this._client, this._buffer);

  final SenderOptions _options;
  final http.Client _client;
  final StringBuffer _buffer;
  Timer? _autoFlushTimer;
  int _rowCount = 0;

  /// Create a sender from configuration options
  static Future<QuestDbSender> fromOptions(SenderOptions options) async {
    final client = http.Client();
    final buffer = StringBuffer();

    return QuestDbSender._(options, client, buffer)
      .._startAutoFlush();
  }

  /// Create a sender from connection string
  static Future<QuestDbSender> fromConfig(String config) {
    final options = SenderOptions.fromString(config);
    return fromOptions(options);
  }

  /// Add data to a table using a builder function
  Future<void> add(
    String tableName,
    void Function(TableBuilder builder) configure,
  ) {
    final builder = TableBuilder._(this, tableName);
    configure(builder);
    return builder._add();
  }

  /// Send raw ILP (InfluxDB Line Protocol) text
  Future<void> sendRaw(String ilpText) async {
    _buffer
      ..write(ilpText)
      ..write('\n');
    _rowCount++;

    if (_rowCount >= _options.autoFlushRows) {
      await flush();
    }
  }

  /// Send multiple ILP lines
  Future<void> sendLines(List<String> lines) async {
    for (final line in lines) {
      _buffer
        ..write(line)
        ..write('\n');
      _rowCount++;
    }

    if (_rowCount >= _options.autoFlushRows) {
      await flush();
    }
  }

  /// Flush buffered data to QuestDB
  Future<void> flush() async {
    if (_buffer.isEmpty) return;

    final data = _buffer.toString();
    _buffer.clear();
    _rowCount = 0;

    await _sendData(data);
  }

  /// Close the sender and cleanup resources
  Future<void> close() async {
    _autoFlushTimer?.cancel();
    await flush();
    _client.close();
  }

  void _startAutoFlush() {
    _autoFlushTimer = Timer.periodic(_options.autoFlushInterval, (_) {
      flush().catchError((Object error) {
        // Log error but don't crash - in production, use proper logging
        // print('Auto-flush failed: $error');
      });
    });
  }

  Future<void> _sendData(String data) async {
    final uri = _buildUri('/write');
    final headers = _buildHeaders();

    final response = await _client
        .post(uri, body: data, headers: headers)
        .timeout(_options.receiveTimeout);

    if (response.statusCode != 204) {
      throw QuestDbException(
        'ILP insert failed: ${response.statusCode} ${response.body}',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  Uri _buildUri(String path) {
    if (_options.isHttps) {
      return Uri.https('${_options.host}:${_options.port}', path);
    } else {
      return Uri.http('${_options.host}:${_options.port}', path);
    }
  }

  Map<String, String> _buildHeaders() {
    final headers = <String, String>{
      'Content-Type': 'text/plain; charset=utf-8',
    };

    if (_options.token != null) {
      headers['Authorization'] = 'Bearer ${_options.token}';
    } else if (_options.username != null && _options.password != null) {
      final credentials = base64Encode(
        utf8.encode('${_options.username}:${_options.password}'),
      );
      headers['Authorization'] = 'Basic $credentials';
    }

    return headers;
  }
}

/// Fluent API builder for table operations
class TableBuilder {
  TableBuilder._(this._sender, this._tableName);

  final QuestDbSender _sender;
  final String _tableName;
  final Map<String, Object?> _fields = {};
  final Map<String, String> _tags = {};
  DateTime? _timestamp;

  /// Add a symbol column (indexed string)
  void symbol(String column, String value) {
    _fields[column] = value;
  }

  /// Add a tag (indexed string for filtering)
  void tag(String key, String value) {
    _tags[key] = value;
  }

  /// Add a string column
  void stringColumn(String column, String value) {
    _fields[column] = '"${value.replaceAll('"', r'\"')}"';
  }

  /// Add a float column
  void floatColumn(String column, double value) {
    _fields[column] = value;
  }

  /// Add an integer column
  void intColumn(String column, int value) {
    _fields[column] = '${value}i';
  }

  /// Add a long column
  void longColumn(String column, int value) {
    _fields[column] = '${value}i';
  }

  /// Add a boolean column
  // ignore: avoid_positional_boolean_parameters
  void boolColumn(String column, bool value) {
    _fields[column] = value ? 'true' : 'false';
  }

  /// Add a timestamp column
  void timestampColumn(String column, DateTime value) {
    _fields[column] = value.millisecondsSinceEpoch * 1000000;
  }

  /// Add an array column
  void arrayColumn(String column, List<Object?> values) {
    final formattedValues = values.map(_formatArrayValue).join(',');
    _fields[column] = '[$formattedValues]';
  }

  /// Set the timestamp for this row
  void at(DateTime timestamp,
      [TimestampUnit unit = TimestampUnit.nanoseconds]) {
    _timestamp = timestamp;
  }

  /// Set timestamp from milliseconds
  void atMillis(int milliseconds) {
    _timestamp = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  /// Set timestamp from microseconds
  void atMicros(int microseconds) {
    _timestamp = DateTime.fromMicrosecondsSinceEpoch(microseconds);
  }

  /// Set timestamp from nanoseconds
  void atNanos(int nanoseconds) {
    // Dart DateTime only supports microseconds precision
    _timestamp = DateTime.fromMicrosecondsSinceEpoch(nanoseconds ~/ 1000);
  }

  /// Add the row to buffer (async) - internal method
  Future<void> _add() async {
    final ilpLine = _buildILPLine();
    await _sender.sendRaw(ilpLine);
  }

  String _buildILPLine() {
    final escapedTable = _tableName
        .replaceAll(',', r'\,')
        .replaceAll(' ', r'\ ')
        .replaceAll('=', r'\=');

    var tagString = '';
    if (_tags.isNotEmpty) {
      final tagParts = _tags.entries.map((entry) {
        final key = entry.key
            .replaceAll(',', r'\,')
            .replaceAll('=', r'\=')
            .replaceAll(' ', r'\ ');
        final value = entry.value
            .replaceAll(',', r'\,')
            .replaceAll('=', r'\=')
            .replaceAll(' ', r'\ ');
        return '$key=$value';
      });
      tagString = ',${tagParts.join(',')}';
    }

    final fieldParts = _fields.entries.map((entry) {
      final key = entry.key
          .replaceAll(',', r'\,')
          .replaceAll('=', r'\=')
          .replaceAll(' ', r'\ ');
      final value = _formatFieldValue(entry.value);
      return '$key=$value';
    });

    if (fieldParts.isEmpty) {
      throw ArgumentError('At least one field is required');
    }

    final fieldString = fieldParts.join(',');
    final timestampString = _timestamp != null
        ? ' ${_timestamp!.millisecondsSinceEpoch * 1000000}'
        : '';

    return '$escapedTable$tagString $fieldString$timestampString';
  }

  String _formatFieldValue(Object? value) {
    if (value == null) {
      throw ArgumentError('Field values cannot be null');
    }

    if (value is String) {
      return value; // Already formatted in column methods
    } else if (value is num) {
      return value.toString();
    } else if (value is bool) {
      return value.toString();
    } else if (value is int) {
      return '${value}i';
    } else {
      return '"${value.toString().replaceAll('"', r'\"')}"';
    }
  }

  String _formatArrayValue(Object? value) {
    if (value == null) {
      return 'null';
    } else if (value is String) {
      return '"${value.replaceAll('"', r'\"')}"';
    } else if (value is num) {
      return value.toString();
    } else if (value is bool) {
      return value.toString();
    } else {
      return '"${value.toString().replaceAll('"', r'\"')}"';
    }
  }
}

/// QuestDB specific exception
class QuestDbException implements Exception {
  const QuestDbException(
    this.message, {
    this.statusCode,
    this.responseBody,
  });

  final String message;
  final int? statusCode;
  final String? responseBody;

  @override
  String toString() {
    var result = 'QuestDbException: $message';
    if (statusCode != null) {
      result += ' (Status: $statusCode)';
    }
    if (responseBody != null && responseBody!.isNotEmpty) {
      result += ' Response: $responseBody';
    }
    return result;
  }
}
