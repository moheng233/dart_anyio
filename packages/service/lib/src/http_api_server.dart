// This server prints startup URLs and simple errors for dev UX.
// In production, route logs through LoggingManager; keeping prints here is intentional.
// ignore_for_file: avoid_print, lines_longer_than_80_chars

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anyio_template/service.dart';
import 'service_manager.dart';

/// HTTP API server for accessing device data
class HttpApiServer {
  HttpApiServer({
    required this.serviceManager,
    this.host = '0.0.0.0',
    this.port = 8080,
  });

  final ServiceManager serviceManager;
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
          return;
        case 'POST':
          _handlePostRequest(request, segments);
          return;
        default:
          _sendError(
            request.response,
            HttpStatus.methodNotAllowed,
            'Method not allowed',
          );
          return;
      }
    } on Exception catch (e) {
      _sendError(
        request.response,
        HttpStatus.internalServerError,
        'Internal server error: $e',
      );
    }
  }

  void _handleGetRequest(HttpRequest request, List<String> segments) {
    if (segments.isEmpty) {
      _sendJson(request.response, {
        'message': 'AnyIO Service API',
        'version': '1.0.0',
      });
      return;
    }

    switch (segments[0]) {
      case 'devices':
        _handleDevicesGet(request, segments);
        return;
      // history/stats 暂时移除或由上层注入后再开放
      case 'health':
        _sendJson(request.response, {
          'status': 'ok',
          'timestamp': DateTime.now().toIso8601String(),
        });
        return;
      default:
        _sendError(request.response, HttpStatus.notFound, 'Endpoint not found');
        return;
    }
  }

  void _handleDevicesGet(HttpRequest request, List<String> segments) {
    if (segments.length == 1) {
      // GET /devices - list all devices
      final devices = serviceManager.channelManager.deviceIds
          .map(
            (id) => {
              'deviceId': id,
              'online': serviceManager.channelManager.getDeviceOnline(id),
            },
          )
          .toList();

      _sendJson(request.response, {'devices': devices});
      return;
    }

    if (segments.length >= 2) {
      final deviceId = segments[1];
      // 存在性校验：目前 deviceIds 为来源
      if (!serviceManager.channelManager.deviceIds.contains(deviceId)) {
        _sendError(
          request.response,
          HttpStatus.notFound,
          'Device not found: $deviceId',
        );
        return;
      }

      if (segments.length == 2) {
        // GET /devices/{deviceId} - get device info and values
        _sendJson(request.response, {
          'deviceId': deviceId,
          'online': serviceManager.channelManager.getDeviceOnline(deviceId),
          'values': serviceManager.channelManager.readAllValues(deviceId),
        });
        return;
      }

      if (segments.length == 3) {
        final command = segments[2];
        switch (command) {
          case 'status':
            // GET /devices/{deviceId}/status - get device online status
            _sendJson(request.response, {
              'deviceId': deviceId,
              'online': serviceManager.channelManager.getDeviceOnline(deviceId),
              'timestamp': DateTime.now().toIso8601String(),
            });
            return;
          case 'values':
            // GET /devices/{deviceId}/values - get all values
            _sendJson(
              request.response,
              serviceManager.channelManager.readAllValues(deviceId),
            );
            return;
          case 'variables':
            // GET /devices/{deviceId}/variables - variable definitions
            final defs = serviceManager.channelManager.getVariableDefinitions(
              deviceId,
            );
            final variables = defs.entries
                .map(
                  (e) => {
                    'id': e.key,
                    'info': e.value.toMap(),
                  },
                )
                .toList();
            _sendJson(
              request.response,
              {'deviceId': deviceId, 'variables': variables},
            );
            return;
          case 'actions':
            // GET /devices/{deviceId}/actions - action definitions
            final defs = serviceManager.channelManager.getActionDefinitions(
              deviceId,
            );
            final actions = defs.entries
                .map(
                  (e) => {
                    'id': e.key,
                    'info': e.value.toMap(),
                  },
                )
                .toList();
            _sendJson(
              request.response,
              {'deviceId': deviceId, 'actions': actions},
            );
            return;
          default:
            _sendError(
              request.response,
              HttpStatus.notFound,
              'Command not found: $command',
            );
            return;
        }
      }

      if (segments.length == 4 && segments[2] == 'variables') {
        final variableId = segments[3];
        // GET /devices/{deviceId}/variables/{variableId} - get specific variable info and value
        final info = serviceManager.channelManager.getVariableInfo(
          deviceId,
          variableId,
        );
        final value = serviceManager.channelManager.readValue(
          deviceId,
          variableId,
        );
        if (info == null && value == null) {
          _sendError(
            request.response,
            HttpStatus.notFound,
            'Variable not found: $variableId',
          );
          return;
        }
        _sendJson(request.response, {
          'deviceId': deviceId,
          'variableId': variableId,
          if (info != null) 'info': info.toMap(),
          'value': value,
          'timestamp': DateTime.now().toIso8601String(),
        });
        return;
      }

      if (segments.length == 4 && segments[2] == 'actions') {
        final actionId = segments[3];
        // GET /devices/{deviceId}/actions/{actionId} - get action info
        final info = serviceManager.channelManager.getActionInfo(
          deviceId,
          actionId,
        );
        if (info == null) {
          _sendError(
            request.response,
            HttpStatus.notFound,
            'Action not found: $actionId',
          );
          return;
        }
        _sendJson(request.response, {
          'deviceId': deviceId,
          'actionId': actionId,
          'info': info.toMap(),
          'timestamp': DateTime.now().toIso8601String(),
        });
        return;
      }

      if (segments.length == 5 &&
          segments[2] == 'variables' &&
          segments[4] == 'events') {
        // GET /devices/{deviceId}/variables/{variableId}/events - SSE stream of variable updates
        final variableId = segments[3];

        // Start SSE using ChannelManager listenValue
        unawaited(_startSseForVariable(request, deviceId, variableId));
        return;
      }

      if (segments.length == 4 &&
          segments[2] == 'status' &&
          segments[3] == 'events') {
        // GET /devices/{deviceId}/status/events - SSE of device online status changes
        unawaited(_startSseForStatus(request, deviceId));
        return;
      }
    }

    _sendError(
      request.response,
      HttpStatus.badRequest,
      'Invalid devices API path',
    );
  }

  Future<void> _startSseForVariable(
    HttpRequest request,
    String deviceId,
    String variableId,
  ) async {
    final response = request.response
      // SSE headers
      ..statusCode = HttpStatus.ok;
    response.headers
      ..set('Content-Type', 'text/event-stream')
      ..set('Cache-Control', 'no-cache, no-transform')
      ..set('Connection', 'keep-alive')
      ..set('X-Accel-Buffering', 'no'); // disable proxy buffering if any

    // Optional: reconnection time for clients (ms)
    response.write('retry: 5000\r\n\r\n');

    await response.flush();

    void sendEvent(Object? value) {
      final payload = jsonEncode({
        'deviceId': deviceId,
        'variableId': variableId,
        'value': value,
        'timestamp': DateTime.now().toIso8601String(),
      });
      response
        ..write('event: update\r\n')
        ..write('data: $payload\r\n\r\n')
        ..flush();
    }

    // Send current value immediately
    sendEvent(serviceManager.channelManager.readValue(deviceId, variableId));

    // Subscribe to variable updates
    final sub = serviceManager.channelManager
        .listenValue(deviceId, variableId)
        .listen(sendEvent, onError: (_) {});

    // Heartbeat to keep connection alive
    final heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
      response
        ..write(': keepalive\r\n\r\n')
        ..flush();
    });

    // Cleanup when client disconnects
    unawaited(
      response.done.whenComplete(() {
        heartbeat.cancel();
        sub.cancel();
      }),
    );
  }

  Future<void> _startSseForStatus(
    HttpRequest request,
    String deviceId,
  ) async {
    final response = request.response..statusCode = HttpStatus.ok;
    response.headers
      ..set('Content-Type', 'text/event-stream')
      ..set('Cache-Control', 'no-cache, no-transform')
      ..set('Connection', 'keep-alive')
      ..set('X-Accel-Buffering', 'no');

    response.write('retry: 5000\r\n\r\n');
    await response.flush();

    void sendEvent({bool? online}) {
      final payload = jsonEncode({
        'deviceId': deviceId,
        'online': online,
        'timestamp': DateTime.now().toIso8601String(),
      });
      response
        ..write('event: status\r\n')
        ..write('data: $payload\r\n\r\n')
        ..flush();
    }

    // Send current status immediately
    sendEvent(online: serviceManager.channelManager.getDeviceOnline(deviceId));

    // Subscribe to status change events
    final sub = serviceManager.channelManager
        .listenEvent<ChannelDeviceStatusEvent>()
        .where((e) => e.deviceId == deviceId)
        .listen((e) => sendEvent(online: e.online), onError: (_) {});

    final heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
      response
        ..write(': keepalive\r\n\r\n')
        ..flush();
    });

    unawaited(
      response.done.whenComplete(() {
        heartbeat.cancel();
        sub.cancel();
      }),
    );
  }

  // history/stats 相关接口已移除

  Future<void> _handlePostRequest(
    HttpRequest request,
    List<String> segments,
  ) async {
    if (segments.length >= 2 && segments[0] == 'devices') {
      final deviceId = segments[1];
      if (!serviceManager.channelManager.deviceIds.contains(deviceId)) {
        _sendError(
          request.response,
          HttpStatus.notFound,
          'Device not found: $deviceId',
        );
        return;
      }

      // POST /devices/{deviceId}/variables/{variableId} - write value to a variable
      if (segments.length == 4 && segments[2] == 'variables') {
        final variableId = segments[3];

        final content = await _readRequestBody(request);
        if (content.trim().isEmpty) {
          _sendError(
            request.response,
            HttpStatus.badRequest,
            'Request body is empty',
          );
          return;
        }

        Object? value;
        try {
          // Accept plain JSON scalar or structured JSON
          value = jsonDecode(content);
        } on FormatException {
          // Fallback to raw string
          value = content;
        }

        try {
          final success = await serviceManager.channelManager.invokeAction(
            deviceId,
            variableId,
            value,
          );
          _sendJson(request.response, {
            'success': success,
            'deviceId': deviceId,
            'variableId': variableId,
            'value': value,
            'timestamp': DateTime.now().toIso8601String(),
          });
        } on Exception catch (e) {
          _sendError(
            request.response,
            HttpStatus.internalServerError,
            'Write failed: $e',
          );
        }
        return;
      }

      // POST /devices/{deviceId}/actions/{actionId} - invoke action
      if (segments.length == 4 && segments[2] == 'actions') {
        final actionId = segments[3];

        final content = await _readRequestBody(request);
        if (content.trim().isEmpty) {
          _sendError(
            request.response,
            HttpStatus.badRequest,
            'Request body is empty',
          );
          return;
        }

        Object? value;
        try {
          value = jsonDecode(content);
        } on FormatException {
          value = content;
        }

        try {
          final success = await serviceManager.channelManager.invokeAction(
            deviceId,
            actionId,
            value,
          );
          _sendJson(request.response, {
            'success': success,
            'deviceId': deviceId,
            'actionId': actionId,
            'value': value,
            'timestamp': DateTime.now().toIso8601String(),
          });
        } on Exception catch (e) {
          _sendError(
            request.response,
            HttpStatus.internalServerError,
            'Action invoke failed: $e',
          );
        }
        return;
      }
    }

    _sendError(
      request.response,
      HttpStatus.badRequest,
      'Invalid POST endpoint',
    );
  }

  Future<String> _readRequestBody(HttpRequest request) async {
    final completer = Completer<String>();
    final buffer = <int>[];

    request.listen(
      buffer.addAll,
      onDone: () => completer.complete(utf8.decode(buffer)),
      onError: completer.completeError,
    );

    return completer.future;
  }

  void _sendJson(HttpResponse response, Object data) {
    response.headers.contentType = ContentType.json;
    response
      ..write(jsonEncode(data))
      ..close();
  }

  void _sendError(HttpResponse response, int statusCode, String message) {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response
      ..write(jsonEncode({'error': message}))
      ..close();
  }
}
