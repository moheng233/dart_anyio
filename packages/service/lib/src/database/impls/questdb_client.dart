import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Represents a single InfluxDB Line Protocol record
class ILPRecord {
  const ILPRecord({
    required this.measurement,
    required this.fields,
    this.tags,
    this.timestamp,
  });

  final String measurement;
  final Map<String, Object?> fields;
  final Map<String, String>? tags;
  final DateTime? timestamp;
}

/// QuestDB REST API client
final class QuestDbApi {
  QuestDbApi({
    required this.host,
    this.port = 9000,
    this.username,
    this.password,
    this.token,
    this.isHttps = false,
  }) : serverUrl = '$host:$port';

  final client = http.Client();

  final bool isHttps;
  final String host;
  final int port;
  final String serverUrl;
  final String? username;
  final String? password;
  final String? token;

  /// Dispose the HTTP client
  void dispose() {
    client.close();
  }

  /// Execute SQL query using /exec endpoint
  Future<dynamic> exec(
    String query, {
    bool? count,
    String? limit,
    bool? nm,
    bool? timings,
    bool? explain,
    bool? quoteLargeNum,
    int? timeout,
  }) async {
    final response = await client.get(
      _uri(serverUrl, '/exec', {
        'query': query,
        if (count != null) 'count': count,
        if (limit != null) 'limit': limit,
        if (nm != null) 'nm': nm,
        if (timings != null) 'timings': timings,
        if (explain != null) 'explain': explain,
        if (quoteLargeNum != null) 'quoteLargeNum': quoteLargeNum,
        if (timeout != null) 'timeout': timeout.toString(),
      }),
      headers: {
        if (timeout != null) 'Statement-Timeout': timeout.toString(),
        if (token != null)
          'Authorization': 'Bearer $token'
        else if (username != null && password != null)
          'Authorization': base64UrlEncode(
            utf8.encode('$username:$password'),
          ),
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Exec failed: ${response.statusCode} ${response.body}');
    }

    return json.decode(response.body);
  }

  /// Export data using /exp endpoint
  Future<String> export(
    String query, {
    String? limit,
    bool? nm,
  }) async {
    final response = await client.get(
      _uri(serverUrl, '/exp', {
        'query': query,
        if (limit != null) 'limit': limit,
        if (nm != null) 'nm': nm,
      }),
      headers: {
        if (token != null)
          'Authorization': 'Bearer $token'
        else if (username != null && password != null)
          'Authorization': base64UrlEncode(
            utf8.encode('$username:$password'),
          ),
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Export failed: ${response.statusCode} ${response.body}');
    }

    return response.body;
  }

  /// Health check using /health endpoint
  Future<Map<String, dynamic>> healthCheck() async {
    final response = await client.get(
      _uri(serverUrl, '/health', {}),
      headers: {
        if (token != null)
          'Authorization': 'Bearer $token'
        else if (username != null && password != null)
          'Authorization': base64UrlEncode(
            utf8.encode('$username:$password'),
          ),
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Health check failed: ${response.statusCode} ${response.body}',
      );
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Import data using /imp endpoint with full parameter support
  Future<Map<String, dynamic>> importData(
    String data, {
    String? name,
    String? schema,
    bool? durable,
    int? maxUncommittedRows,
    int? commitLag,
    String? partitionBy,
    String? timestamp,
    String? fmt,
    bool? overwrite,
    bool? create,
    String? atomicity,
    String? delimiter,
    bool? forceHeader,
    String? skipLev,
    int? o3MaxLag,
  }) async {
    final response = await client.post(
      _uri(serverUrl, '/imp', {
        if (name != null) 'name': name,
        if (schema != null) 'schema': schema,
        if (durable != null) 'durable': durable,
        if (maxUncommittedRows != null)
          'maxUncommittedRows': maxUncommittedRows.toString(),
        if (commitLag != null) 'commitLag': commitLag.toString(),
        if (partitionBy != null) 'partitionBy': partitionBy,
        if (timestamp != null) 'timestamp': timestamp,
        if (fmt != null) 'fmt': fmt,
        if (overwrite != null) 'overwrite': overwrite,
        if (create != null) 'create': create,
        if (atomicity != null) 'atomicity': atomicity,
        if (delimiter != null) 'delimiter': delimiter,
        if (forceHeader != null) 'forceHeader': forceHeader,
        if (skipLev != null) 'skipLev': skipLev,
        if (o3MaxLag != null) 'o3MaxLag': o3MaxLag.toString(),
      }),
      body: data,
      headers: {
        'Content-Type': 'text/plain',
        if (token != null)
          'Authorization': 'Bearer $token'
        else if (username != null && password != null)
          'Authorization': base64UrlEncode(
            utf8.encode('$username:$password'),
          ),
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Import failed: ${response.statusCode} ${response.body}');
    }

    // Return JSON response if fmt=json, otherwise return raw text
    if (fmt == 'json') {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    return {'data': response.body};
  }

  /// Insert single record into table
  Future<void> insert(
    String tableName,
    Map<String, Object?> values, {
    bool createTableIfNotExists = false,
  }) async {
    final columns = values.keys.toList();
    final vals = columns.map((col) => _formatSqlValue(values[col])).toList();

    var query = 'INSERT ';
    if (createTableIfNotExists) {
      query += 'OR IGNORE ';
    }
    query += 'INTO $tableName (${columns.join(', ')}) ';
    query += 'VALUES (${vals.join(', ')});';

    await exec(query);
  }

  /// Insert multiple records into table using batch insert
  Future<void> insertBatch(
    String tableName,
    List<Map<String, Object?>> records, {
    bool createTableIfNotExists = false,
    int batchSize = 1000,
  }) async {
    if (records.isEmpty) return;

    final columns = records.first.keys.toList();

    for (var i = 0; i < records.length; i += batchSize) {
      final batch = records.skip(i).take(batchSize).toList();
      final values = batch
          .map((record) {
            final vals = columns
                .map((col) => _formatSqlValue(record[col]))
                .toList();
            return '(${vals.join(', ')})';
          })
          .join(', ');

      var query = 'INSERT ';
      if (createTableIfNotExists) {
        query += 'OR IGNORE ';
      }
      query += 'INTO $tableName (${columns.join(', ')}) ';
      query += 'VALUES $values;';

      await exec(query);
    }
  }

  /// Helper method to format values for SQL queries
  String _formatSqlValue(Object? value) {
    if (value == null) return 'NULL';
    if (value is String) return "'${value.replaceAll("'", "''")}'";
    if (value is num) return value.toString();
    if (value is bool) return value ? 'true' : 'false';
    if (value is DateTime) return "'${value.toUtc().toIso8601String()}'";
    return "'${value.toString().replaceAll("'", "''")}'";
  }

  Uri _uri(
    String authority,
    String unencodedPath,
    Map<String, dynamic> queryParameters,
  ) {
    if (isHttps) {
      return Uri.https(authority, unencodedPath, queryParameters);
    }
    return Uri.http(authority, unencodedPath, queryParameters);
  }
}

/// QuestDB InfluxDB Line Protocol HTTP client
final class QuestDbIlpClient {
  QuestDbIlpClient({
    required this.host,
    this.port = 9000,
    this.username,
    this.password,
    this.token,
    this.isHttps = false,
  }) : serverUrl = '$host:$port';

  final String host;
  final int port;
  final String serverUrl;
  final String? username;
  final String? password;
  final String? token;
  final bool isHttps;

  final client = http.Client();

  /// Dispose the HTTP client
  void dispose() {
    client.close();
  }

  /// Send single or multiple ILP data lines
  Future<void> sendLines(List<String> lines) async {
    final ilpText = lines.join('\n');
    await _sendILPData(ilpText);
  }

  /// Send raw ILP text
  Future<void> sendRaw(String ilpText) async {
    await _sendILPData(ilpText);
  }

  /// Send ILP data to QuestDB via HTTP POST
  Future<void> _sendILPData(String data) async {
    final uri = _uri(serverUrl, '/write', <String, dynamic>{});
    print('ILP Request URL: $uri');
    print('ILP Request Data: $data');

    final response = await client.post(
      uri,
      body: data,
      headers: {
        'Content-Type': 'text/plain; charset=utf-8',
        if (token != null)
          'Authorization': 'Bearer $token'
        else if (username != null && password != null)
          'Authorization': base64UrlEncode(
            utf8.encode('$username:$password'),
          ),
      },
    );

    print('ILP Response Status: ${response.statusCode}');
    print('ILP Response Body: ${response.body}');

    if (response.statusCode != 204) {
      throw Exception(
        'ILP insert failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// Send ILPRecord batch
  Future<void> sendRecords(List<ILPRecord> records) async {
    final lines = records
        .map(
          (r) => _buildILPLine(
            r.measurement,
            r.fields,
            r.tags,
            r.timestamp,
          ),
        )
        .toList();
    await sendLines(lines);
  }

  /// Build ILP line (compatible with QuestDbApi)
  String _buildILPLine(
    String measurement,
    Map<String, Object?> fields,
    Map<String, String>? tags,
    DateTime? timestamp,
  ) {
    final escapedMeasurement = measurement
        .replaceAll(',', r'\,')
        .replaceAll(' ', r'\ ');
    var tagString = '';
    if (tags != null && tags.isNotEmpty) {
      final tagParts = tags.entries.map((entry) {
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
    final fieldParts = fields.entries.map((entry) {
      final key = entry.key
          .replaceAll(',', r'\,')
          .replaceAll('=', r'\=')
          .replaceAll(' ', r'\ ');
      final value = _formatILPFieldValue(entry.value);
      return '$key=$value';
    });
    final fieldString = fieldParts.join(',');
    final timestampString = timestamp != null
        ? ' ${timestamp.millisecondsSinceEpoch * 1000000}'
        : '';
    return '$escapedMeasurement$tagString $fieldString$timestampString';
  }

  String _formatILPFieldValue(Object? value) {
    if (value == null) {
      throw ArgumentError('ILP field values cannot be null');
    }
    if (value is String) {
      return '"${value.replaceAll('"', r'\"')}"';
    } else if (value is num) {
      return value.toString();
    } else if (value is bool) {
      return value ? 'true' : 'false';
    } else if (value is DateTime) {
      return value.millisecondsSinceEpoch.toString();
    } else {
      return '"${value.toString().replaceAll('"', r'\"')}"';
    }
  }

  Uri _uri(
    String authority,
    String unencodedPath,
    Map<String, dynamic> queryParameters,
  ) {
    if (isHttps) {
      return Uri.https(authority, unencodedPath, queryParameters);
    }
    return Uri.http(authority, unencodedPath, queryParameters);
  }
}
