import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anyio_template/service.dart';

import 'service_manager.dart';
import 'time_series.dart';

/// HTTP API server for accessing device data
class HttpApiServer {
  HttpApiServer({
    required this.serviceManager,
    this.timeSeriesDb,
    this.host = '0.0.0.0',
    this.port = 8080,
  });

  final ServiceManager serviceManager;
  final TimeSeriesDatabase? timeSeriesDb;
  final String host;
  final int port;

  HttpServer? _server;

  /// Start the HTTP server
  Future<void> start() async {
    if (_server != null) {
      throw StateError('Server is already running');
    }

    _server = await HttpServer.bind(host, port);
    print('HTTP API server started on $host:$port');

    await for (final request in _server!) {
      _handleRequest(request);
    }
  }

  /// Stop the HTTP server
  Future<void> stop() async {
    await _server?.close();
    _server = null;
    print('HTTP API server stopped');
  }

  void _handleRequest(HttpRequest request) {
    // Set CORS headers
    request.response.headers
      ..add('Access-Control-Allow-Origin', '*')
      ..add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..add('Access-Control-Allow-Headers', 'Content-Type');

    if (request.method == 'OPTIONS') {
      request.response
        ..statusCode = HttpStatus.ok
        ..close();
      return;
    }

    try {
      final uri = request.uri;
      final segments = uri.pathSegments;

      switch (request.method) {
        case 'GET':
          _handleGetRequest(request, segments);
          break;
        case 'POST':
          _handlePostRequest(request, segments);
          break;
        default:
          _sendError(request.response, HttpStatus.methodNotAllowed, 'Method not allowed');
      }
    } catch (e) {
      _sendError(request.response, HttpStatus.internalServerError, 'Internal server error: $e');
    }
  }

  void _handleGetRequest(HttpRequest request, List<String> segments) {
    if (segments.isEmpty) {
      _sendJson(request.response, {'message': 'AnyIO Service API', 'version': '1.0.0'});
      return;
    }

    switch (segments[0]) {
      case 'devices':
        _handleDevicesGet(request, segments);
        break;
      case 'history':
        _handleHistoryGet(request, segments);
        break;
      case 'stats':
        _handleStatsGet(request, segments);
        break;
      case 'health':
        _sendJson(request.response, {'status': 'ok', 'timestamp': DateTime.now().toIso8601String()});
        break;
      default:
        _sendError(request.response, HttpStatus.notFound, 'Endpoint not found');
    }
  }

  void _handleDevicesGet(HttpRequest request, List<String> segments) {
    if (segments.length == 1) {
      // GET /devices - list all devices
      final devices = serviceManager.devices.map((device) => {
        'deviceId': device.deviceId,
        'points': device.points.length,
        'template': device.template.info.name,
      }).toList();
      
      _sendJson(request.response, {'devices': devices});
      return;
    }

    if (segments.length >= 2) {
      final deviceId = segments[1];
      final device = serviceManager.getDevice(deviceId);
      
      if (device == null) {
        _sendError(request.response, HttpStatus.notFound, 'Device not found: $deviceId');
        return;
      }

      if (segments.length == 2) {
        // GET /devices/{deviceId} - get device info and values
        _sendJson(request.response, {
          'deviceId': device.deviceId,
          'template': device.template.info.name,
          'templateVersion': device.template.info.version,
          'displayName': device.template.info.displayName,
          'values': device.values,
          'points': device.template.points.map((key, value) => MapEntry(key, {
            'type': value.runtimeType.toString(),
            'access': value.access.toString(),
            'displayName': value.displayName,
            'detailed': value.detailed,
          })),
        });
        return;
      }

      if (segments.length == 3) {
        final command = segments[2];
        switch (command) {
          case 'values':
            // GET /devices/{deviceId}/values - get all values
            _sendJson(request.response, device.values);
            break;
          case 'points':
            // GET /devices/{deviceId}/points - get point definitions
            final points = device.template.points.map((key, value) => MapEntry(key, {
              'type': value.runtimeType.toString(),
              'access': value.access.toString(),
              'displayName': value.displayName,
              'detailed': value.detailed,
            }));
            _sendJson(request.response, points);
            break;
          default:
            _sendError(request.response, HttpStatus.notFound, 'Command not found: $command');
        }
        return;
      }

      if (segments.length == 4 && segments[2] == 'points') {
        final pointId = segments[3];
        // GET /devices/{deviceId}/points/{pointId} - get specific point value
        final value = device.read(pointId);
        if (value != null || device.template.points.containsKey(pointId)) {
          _sendJson(request.response, {
            'deviceId': deviceId,
            'pointId': pointId,
            'value': value,
            'timestamp': DateTime.now().toIso8601String(),
          });
        } else {
          _sendError(request.response, HttpStatus.notFound, 'Point not found: $pointId');
        }
        return;
      }
    }

    _sendError(request.response, HttpStatus.badRequest, 'Invalid devices API path');
  }

  void _handleHistoryGet(HttpRequest request, List<String> segments) {
    if (timeSeriesDb == null) {
      _sendError(request.response, HttpStatus.serviceUnavailable, 'Time-series database not available');
      return;
    }

    if (segments.length < 2) {
      _sendError(request.response, HttpStatus.badRequest, 'Device ID required');
      return;
    }

    final deviceId = segments[1];
    final pointId = segments.length > 2 ? segments[2] : null;
    
    // Parse query parameters
    final queryParams = request.uri.queryParameters;
    final startTime = queryParams['start'] != null ? DateTime.tryParse(queryParams['start']!) : null;
    final endTime = queryParams['end'] != null ? DateTime.tryParse(queryParams['end']!) : null;
    final limit = int.tryParse(queryParams['limit'] ?? '1000') ?? 1000;

    final query = HistoryQuery(
      deviceId: deviceId,
      pointId: pointId,
      startTime: startTime,
      endTime: endTime,
      limit: limit,
    );

    timeSeriesDb!.queryHistory(query).then((points) {
      _sendJson(request.response, {
        'deviceId': deviceId,
        'pointId': pointId,
        'query': {
          'startTime': startTime?.toIso8601String(),
          'endTime': endTime?.toIso8601String(),
          'limit': limit,
        },
        'data': points.map((p) => p.toJson()).toList(),
      });
    }).catchError((e) {
      _sendError(request.response, HttpStatus.internalServerError, 'Failed to query history: $e');
    });
  }

  void _handleStatsGet(HttpRequest request, List<String> segments) {
    if (timeSeriesDb is InMemoryTimeSeriesDatabase) {
      final stats = (timeSeriesDb as InMemoryTimeSeriesDatabase).getStatistics();
      _sendJson(request.response, stats);
    } else {
      _sendJson(request.response, {
        'devices': serviceManager.devices.length,
        'deviceIds': serviceManager.deviceIds.toList(),
      });
    }
  }

  Future<void> _handlePostRequest(HttpRequest request, List<String> segments) async {
    if (segments.length >= 2 && segments[0] == 'devices') {
      final deviceId = segments[1];
      final device = serviceManager.getDevice(deviceId);
      
      if (device == null) {
        _sendError(request.response, HttpStatus.notFound, 'Device not found: $deviceId');
        return;
      }

      if (segments.length == 3 && segments[2] == 'write') {
        // POST /devices/{deviceId}/write - write to device
        final content = await _readRequestBody(request);
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        final pointId = data['pointId'] as String?;
        final value = data['value'];
        
        if (pointId == null) {
          _sendError(request.response, HttpStatus.badRequest, 'Missing pointId');
          return;
        }

        try {
          final success = await device.writeAsync(pointId, value);
          _sendJson(request.response, {
            'success': success,
            'deviceId': deviceId,
            'pointId': pointId,
            'value': value,
            'timestamp': DateTime.now().toIso8601String(),
          });
        } catch (e) {
          _sendError(request.response, HttpStatus.internalServerError, 'Write failed: $e');
        }
        return;
      }
    }

    _sendError(request.response, HttpStatus.badRequest, 'Invalid POST endpoint');
  }

  Future<String> _readRequestBody(HttpRequest request) async {
    final completer = Completer<String>();
    final buffer = <int>[];
    
    request.listen(
      (data) => buffer.addAll(data),
      onDone: () => completer.complete(utf8.decode(buffer)),
      onError: completer.completeError,
    );
    
    return completer.future;
  }

  void _sendJson(HttpResponse response, Object data) {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
    response.close();
  }

  void _sendError(HttpResponse response, int statusCode, String message) {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode({'error': message}));
    response.close();
  }
}