import 'dart:async';
import 'dart:convert';

import 'package:anyio_template/service.dart';
import 'package:async/async.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'data_gateway.dart';

part 'data_gateway_api.g.dart';
part 'data_gateway_api.mapper.dart';

// Response classes using dart_mappable

@MappableClass()
class ErrorResponse with ErrorResponseMappable {
  const ErrorResponse({required this.error});
  final String error;
}

@MappableClass()
class DeviceSummary with DeviceSummaryMappable {
  const DeviceSummary({required this.deviceId, required this.online});
  final String deviceId;
  final bool online;
}

@MappableClass()
class DeviceListResponse with DeviceListResponseMappable {
  const DeviceListResponse({required this.devices});
  final List<DeviceSummary> devices;
}

@MappableClass()
class DeviceResponse with DeviceResponseMappable {
  const DeviceResponse({
    required this.deviceId,
    required this.online,
    required this.values,
  });
  final String deviceId;
  final bool online;
  final Map<String, dynamic> values;
}

@MappableClass()
class DeviceStatusResponse with DeviceStatusResponseMappable {
  const DeviceStatusResponse({
    required this.deviceId,
    required this.online,
    required this.timestamp,
  });
  final String deviceId;
  final bool online;
  final String timestamp;
}

@MappableClass()
class VariableSummary with VariableSummaryMappable {
  const VariableSummary({required this.id, required this.info});
  final String id;
  final Map<String, dynamic> info;
}

@MappableClass()
class VariableListResponse with VariableListResponseMappable {
  const VariableListResponse({required this.deviceId, required this.variables});
  final String deviceId;
  final List<VariableSummary> variables;
}

@MappableClass()
class ActionSummary with ActionSummaryMappable {
  const ActionSummary({required this.id, required this.info});
  final String id;
  final Map<String, dynamic> info;
}

@MappableClass()
class ActionListResponse with ActionListResponseMappable {
  const ActionListResponse({required this.deviceId, required this.actions});
  final String deviceId;
  final List<ActionSummary> actions;
}

@MappableClass()
class VariableResponse with VariableResponseMappable {
  const VariableResponse({
    required this.deviceId,
    required this.variableId,
    this.info,
    required this.value,
    required this.timestamp,
  });
  final String deviceId;
  final String variableId;
  final Map<String, dynamic>? info;
  final dynamic value;
  final String timestamp;
}

@MappableClass()
class ActionResponse with ActionResponseMappable {
  const ActionResponse({
    required this.deviceId,
    required this.actionId,
    required this.info,
    required this.timestamp,
  });
  final String deviceId;
  final String actionId;
  final Map<String, dynamic> info;
  final String timestamp;
}

@MappableClass()
class WriteResponse with WriteResponseMappable {
  const WriteResponse({
    required this.success,
    required this.deviceId,
    required this.variableId,
    required this.value,
    required this.timestamp,
  });
  final bool success;
  final String deviceId;
  final String variableId;
  final dynamic value;
  final String timestamp;
}

@MappableClass()
class InvokeResponse with InvokeResponseMappable {
  const InvokeResponse({
    required this.success,
    required this.deviceId,
    required this.actionId,
    required this.value,
    required this.timestamp,
  });
  final bool success;
  final String deviceId;
  final String actionId;
  final dynamic value;
  final String timestamp;
}

@MappableClass()
class HealthResponse with HealthResponseMappable {
  const HealthResponse({required this.status, required this.timestamp});
  final String status;
  final String timestamp;
}

final class DataGateWayApiService {
  DataGateWayApiService({required this.gateway});

  final DataGateway gateway;

  Router get router => _$DataGateWayApiServiceRouter(this);

  @Route.get('/devices')
  Future<Response> listDevices(Request request) async {
    final devices = gateway.deviceIds
        .map(
          (id) =>
              DeviceSummary(deviceId: id, online: gateway.getDeviceOnline(id)),
        )
        .toList();
    final response = DeviceListResponse(devices: devices);
    return Response.ok(
      jsonEncode(response.toMap()),
      headers: {'content-type': 'application/json'},
    );
  }

  @Route.get('/devices/<deviceId>')
  Future<Response> getDevice(Request request, String deviceId) async {
    if (!gateway.deviceIds.contains(deviceId)) {
      final error = ErrorResponse(error: 'Device not found: $deviceId');
      return Response.notFound(
        jsonEncode(error.toMap()),
        headers: {'content-type': 'application/json'},
      );
    }

    final response = DeviceResponse(
      deviceId: deviceId,
      online: gateway.getDeviceOnline(deviceId),
      values: gateway.readAllValues(deviceId),
    );
    return Response.ok(
      jsonEncode(response.toMap()),
      headers: {'content-type': 'application/json'},
    );
  }

  @Route.get('/devices/<deviceId>/status')
  Future<Response> getDeviceStatus(Request request, String deviceId) async {
    if (!gateway.deviceIds.contains(deviceId)) {
      final error = ErrorResponse(error: 'Device not found: $deviceId');
      return Response.notFound(
        jsonEncode(error.toMap()),
        headers: {'content-type': 'application/json'},
      );
    }

    final response = DeviceStatusResponse(
      deviceId: deviceId,
      online: gateway.getDeviceOnline(deviceId),
      timestamp: DateTime.now().toIso8601String(),
    );
    return Response.ok(
      jsonEncode(response.toMap()),
      headers: {'content-type': 'application/json'},
    );
  }

  @Route.get('/devices/<deviceId>/values')
  Future<Response> getDeviceValues(Request request, String deviceId) async {
    if (!gateway.deviceIds.contains(deviceId)) {
      return Response.notFound(
        jsonEncode({'error': 'Device not found: $deviceId'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final values = gateway.readAllValues(deviceId);

    return Response.ok(
      jsonEncode(values),
      headers: {'content-type': 'application/json'},
    );
  }

  @Route.get('/devices/<deviceId>/variables')
  Future<Response> getDeviceVariables(Request request, String deviceId) async {
    if (!gateway.deviceIds.contains(deviceId)) {
      return Response.notFound(
        jsonEncode({'error': 'Device not found: $deviceId'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final defs = gateway.getVariableDefinitions(deviceId);
    final variables = defs.entries
        .map(
          (e) => {
            'id': e.key,
            'info': e.value.toMap(),
          },
        )
        .toList();

    return Response.ok(
      jsonEncode({'deviceId': deviceId, 'variables': variables}),
      headers: {'content-type': 'application/json'},
    );
  }

  @Route.get('/devices/<deviceId>/actions')
  Future<Response> getDeviceActions(Request request, String deviceId) async {
    if (!gateway.deviceIds.contains(deviceId)) {
      return Response.notFound(
        jsonEncode({'error': 'Device not found: $deviceId'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final defs = gateway.getActionDefinitions(deviceId);
    final actions = defs.entries
        .map(
          (e) => {
            'id': e.key,
            'info': e.value.toMap(),
          },
        )
        .toList();

    return Response.ok(
      jsonEncode({'deviceId': deviceId, 'actions': actions}),
      headers: {'content-type': 'application/json'},
    );
  }

  @Route.get('/devices/<deviceId>/variables/<variableId>')
  Future<Response> getDeviceVariable(
    Request request,
    String deviceId,
    String variableId,
  ) async {
    if (!gateway.deviceIds.contains(deviceId)) {
      return Response.notFound(
        jsonEncode({'error': 'Device not found: $deviceId'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final info = gateway.getVariableInfo(deviceId, variableId);
    final value = gateway.readValue(deviceId, variableId);

    if (info == null && value == null) {
      return Response.notFound(
        jsonEncode({'error': 'Variable not found: $variableId'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final data = {
      'deviceId': deviceId,
      'variableId': variableId,
      if (info != null) 'info': info.toMap(),
      'value': value,
      'timestamp': DateTime.now().toIso8601String(),
    };

    return Response.ok(
      jsonEncode(data),
      headers: {'content-type': 'application/json'},
    );
  }

  @Route.get('/devices/<deviceId>/actions/<actionId>')
  Future<Response> getDeviceAction(
    Request request,
    String deviceId,
    String actionId,
  ) async {
    if (!gateway.deviceIds.contains(deviceId)) {
      return Response.notFound(
        jsonEncode({'error': 'Device not found: $deviceId'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final info = gateway.getActionInfo(deviceId, actionId);

    if (info == null) {
      return Response.notFound(
        jsonEncode({'error': 'Action not found: $actionId'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final data = {
      'deviceId': deviceId,
      'actionId': actionId,
      'info': info.toMap(),
      'timestamp': DateTime.now().toIso8601String(),
    };

    return Response.ok(
      jsonEncode(data),
      headers: {'content-type': 'application/json'},
    );
  }

  @Route.get('/devices/<deviceId>/variables/<variableId>/events')
  Future<Response> getDeviceVariableEvents(
    Request request,
    String deviceId,
    String variableId,
  ) async {
    if (!gateway.deviceIds.contains(deviceId)) {
      return Response.notFound(
        jsonEncode({'error': 'Device not found: $deviceId'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final stream = gateway.listenValue(deviceId, variableId).map((value) {
      final payload = jsonEncode({
        'deviceId': deviceId,
        'variableId': variableId,
        'value': value,
        'timestamp': DateTime.now().toIso8601String(),
      });
      return 'event: update\r\ndata: $payload\r\n\r\n';
    });

    // Add heartbeat
    final heartbeat = Stream.periodic(
      const Duration(seconds: 15),
      (_) => ': keepalive\r\n\r\n',
    );

    return Response.ok(
      StreamGroup.merge([stream, heartbeat]).transform(utf8.encoder),
      headers: {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
        'connection': 'keep-alive',
      },
    );
  }

  @Route.get('/devices/<deviceId>/status/events')
  Future<Response> getDeviceStatusEvents(
    Request request,
    String deviceId,
  ) async {
    if (!gateway.deviceIds.contains(deviceId)) {
      return Response.notFound(
        jsonEncode({'error': 'Device not found: $deviceId'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final stream = gateway
        .listenEvent<ChannelDeviceStatusEvent>()
        .where((e) => e.deviceId == deviceId)
        .map((e) {
          final payload = jsonEncode({
            'deviceId': deviceId,
            'online': e.online,
            'timestamp': DateTime.now().toIso8601String(),
          });
          return 'event: status\r\ndata: $payload\r\n\r\n';
        });

    final heartbeat = Stream.periodic(
      const Duration(seconds: 15),
      (_) => ': keepalive\r\n\r\n',
    );

    return Response.ok(
      StreamGroup.merge([stream, heartbeat]).transform(utf8.encoder),
      headers: {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
        'connection': 'keep-alive',
      },
    );
  }

  @Route.post('/devices/<deviceId>/variables/<variableId>')
  Future<Response> writeDeviceVariable(
    Request request,
    String deviceId,
    String variableId,
  ) async {
    if (!gateway.deviceIds.contains(deviceId)) {
      return Response.notFound(
        jsonEncode({'error': 'Device not found: $deviceId'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final body = await request.readAsString();
    if (body.trim().isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Request body is empty'}),
        headers: {'content-type': 'application/json'},
      );
    }

    Object? value;
    try {
      value = jsonDecode(body);
    } on FormatException {
      value = body;
    }

    try {
      final success = await gateway.invokeAction(deviceId, variableId, value);
      final data = {
        'success': success,
        'deviceId': deviceId,
        'variableId': variableId,
        'value': value,
        'timestamp': DateTime.now().toIso8601String(),
      };

      return Response.ok(
        jsonEncode(data),
        headers: {'content-type': 'application/json'},
      );
    } on Exception catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Write failed: $e'}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  @Route.post('/devices/<deviceId>/actions/<actionId>')
  Future<Response> invokeDeviceAction(
    Request request,
    String deviceId,
    String actionId,
  ) async {
    if (!gateway.deviceIds.contains(deviceId)) {
      return Response.notFound(
        jsonEncode({'error': 'Device not found: $deviceId'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final body = await request.readAsString();
    if (body.trim().isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Request body is empty'}),
        headers: {'content-type': 'application/json'},
      );
    }

    Object? value;
    try {
      value = jsonDecode(body);
    } on FormatException {
      value = body;
    }

    try {
      final success = await gateway.invokeAction(deviceId, actionId, value);
      final data = {
        'success': success,
        'deviceId': deviceId,
        'actionId': actionId,
        'value': value,
        'timestamp': DateTime.now().toIso8601String(),
      };

      return Response.ok(
        jsonEncode(data),
        headers: {'content-type': 'application/json'},
      );
    } on Exception catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Action invoke failed: $e'}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  @Route.get('/health')
  Future<Response> health(Request request) async {
    return Response.ok(
      jsonEncode({
        'status': 'ok',
        'timestamp': DateTime.now().toIso8601String(),
      }),
      headers: {'content-type': 'application/json'},
    );
  }
}
