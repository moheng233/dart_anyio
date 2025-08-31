import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:anyio_modbus/modbus_client.dart';
import 'package:anyio_template/service.dart';
import 'package:anyio_template/tcp_connection_manager.dart';

import 'session.dart';
import 'template.dart';

// Constants
const String _modbusS2cPortName = 'modbus_s2c';
const String _connectionTypeTcp = 'tcp';
const String _connectionTypeUnix = 'unix';
const String _connectionTypeUnknown = 'unknown';
const String _performanceEventReconnectAttempt = 'conn.reconnect.attempt';
const String _performanceEventReconnectSuccess = 'conn.reconnect.success';
const String _performanceEventReconnectFail = 'conn.reconnect.fail';
const String _performanceEventReconnect = 'conn.reconnect';

typedef _ModbusClientEntry = ({
  ModbusClient? client,
  int refCount,
  Socket? socket,
  ModbusTransportOption transport,
  bool isRtu,
  bool reconnecting,
});

typedef _SessionSpec = ({
  ChannelOptionForModbus channelOption,
  ChannelTemplateForModbus templateOption,
});

typedef _ConnectionInfo = ({
  ModbusTransportOption transport,
  bool isRtu,
  Set<String> deviceIds,
});

class _ModbusAdapterRunner {
  _ModbusAdapterRunner(this.devices, this.c2sPort)
    : readCtrl = StreamController<ChannelBaseEvent>(sync: true),
      writeCtrl = StreamController<DeviceBaseEvent>.broadcast(sync: true) {
    tcpManager = TcpConnectionManager(
      onConnectionStateChanged: _onConnectionStateChanged,
      onConnectionEstablished: _onConnectionEstablished,
      onConnectionLost: _onConnectionLost,
    );
  }

  final List<ChannelOptionGroup> devices;
  final SendPort c2sPort;

  // Per-factory streams
  final StreamController<ChannelBaseEvent> readCtrl;
  final StreamController<DeviceBaseEvent> writeCtrl;

  // TCP connection manager - initialized in constructor
  late final TcpConnectionManager tcpManager;

  // Pooling and session state
  final sessions = <String, ChannelSessionForModbus>{};
  final clients = <String, _ModbusClientEntry>{};
  final connDevices = <String, Set<String>>{}; // connectionKey -> deviceIds
  final sessionSpecs = <String, _SessionSpec>{};
  final connectionInfos = <String, _ConnectionInfo>{};

  String _clientKey(ChannelOptionForModbus ch) {
    final t = ch.transport;
    if (t is ModbusTcpOption) return '$_connectionTypeTcp:${t.host}:${t.port}';
    if (t is ModbusUnixSocketOption) return '$_connectionTypeUnix:${t.path}';
    return _connectionTypeUnknown;
  }

  TcpConnectionConfig _transportToConfig(ModbusTransportOption transport) {
    if (transport is ModbusTcpOption) {
      return TcpConnectionConfig.tcp(transport.host, transport.port);
    }
    if (transport is ModbusUnixSocketOption) {
      return TcpConnectionConfig.unix(transport.path);
    } 
    throw UnsupportedError('Unsupported transport: ${transport.runtimeType}');
  }

  void _notifyConnectionDown(String key, Object? error) {
    final ids = connDevices[key];
    if (ids == null || ids.isEmpty) return;

    for (final id in ids) {
      sessions[id]?.stop();
      readCtrl.add(ChannelDeviceStatusEvent(id, false));
    }
  }

  void _reportPerformanceEvent(String deviceId, String eventName, int count) {
    readCtrl.add(ChannelPerformanceCountEvent(deviceId, eventName, count));
  }

  void _reportPerformanceTime(
    String deviceId,
    String eventName,
    Duration diffTime,
    DateTime startTime,
    DateTime endTime,
  ) {
    readCtrl.add(
      ChannelPerformanceTimeEvent(
        deviceId,
        eventName,
        diffTime: diffTime,
        startTime: startTime,
        endTime: endTime,
      ),
    );
  }

  // TCP Connection Manager Callbacks
  void _onConnectionStateChanged(
    String connectionKey,
    TcpConnectionState state,
  ) {
    switch (state) {
      case TcpConnectionState.connected:
        _handleConnectionEstablished(connectionKey);
      case TcpConnectionState.disconnected:
        _notifyConnectionDown(connectionKey, null);
      case TcpConnectionState.reconnecting:
        _reportReconnectAttempt(connectionKey);
      case TcpConnectionState.connecting:
        // No specific action needed for connecting state
        break;
    }
  }

  void _onConnectionEstablished(String connectionKey, Socket socket) {
    _handleConnectionEstablishedWithSocket(connectionKey, socket);
  }

  void _onConnectionLost(String connectionKey, Object? error) {
    _notifyConnectionDown(connectionKey, error);
    _reportReconnectFailure(connectionKey);
  }

  void _reportReconnectAttempt(String connectionKey) {
    final deviceIds = connDevices[connectionKey] ?? const <String>{};
    for (final deviceId in deviceIds) {
      _reportPerformanceEvent(deviceId, _performanceEventReconnectAttempt, 1);
    }
  }

  void _reportReconnectFailure(String connectionKey) {
    final deviceIds = connDevices[connectionKey] ?? const <String>{};
    for (final deviceId in deviceIds) {
      _reportPerformanceEvent(deviceId, _performanceEventReconnectFail, 1);
    }
  }

  void _handleConnectionEstablished(String connectionKey) {
    final connInfo = connectionInfos[connectionKey];
    if (connInfo == null) return;

    final socket = tcpManager.getSocket(connectionKey);
    if (socket == null) return;

    _handleConnectionEstablishedWithSocket(connectionKey, socket);
  }

  void _handleConnectionEstablishedWithSocket(
    String connectionKey,
    Socket socket,
  ) {
    final connInfo = connectionInfos[connectionKey];
    if (connInfo == null) return;

    final startTime = DateTime.now();

    try {
      _createModbusClient(connectionKey, socket, connInfo, startTime);
    } catch (error, stackTrace) {
      // Handle client creation failure - log error but don't crash
      print('Failed to create Modbus client for $connectionKey: $error');
      print('Stack trace: $stackTrace');
    }
  }

  void _createModbusClient(
    String connectionKey,
    Socket socket,
    _ConnectionInfo connInfo,
    DateTime startTime,
  ) {
    // Create Modbus client
    final client = ModbusClient(socket, socket, isRtu: connInfo.isRtu);

    // Store client
    clients[connectionKey] = (
      client: client,
      refCount: connInfo.deviceIds.length,
      socket: socket,
      transport: connInfo.transport,
      isRtu: connInfo.isRtu,
      reconnecting: false,
    );

    // Create sessions for all devices on this connection
    for (final deviceId in connInfo.deviceIds) {
      _createDeviceSession(deviceId, client, startTime);
    }
  }

  void _createDeviceSession(
    String deviceId,
    ModbusClient client,
    DateTime startTime,
  ) {
    final old = sessions[deviceId];
    if (old != null) {
      old.stop();
    }

    final spec = sessionSpecs[deviceId];
    if (spec == null) return;

    final session = ChannelSessionForModbus(
      deviceId,
      write: writeCtrl.stream.where(
        (e) => e is DeviceActionInvokeEvent && e.deviceId == deviceId,
      ),
      client: client,
      channelOption: spec.channelOption,
      templateOption: spec.templateOption,
    );

    sessions[deviceId] = session;
    session.read.listen(readCtrl.add);
    session.open();

    // Report device online and success metrics
    _reportDeviceOnline(deviceId, startTime);
  }

  void _reportDeviceOnline(String deviceId, DateTime startTime) {
    final endTime = DateTime.now();

    readCtrl
      ..add(ChannelDeviceStatusEvent(deviceId, true))
      ..add(
        ChannelPerformanceCountEvent(
          deviceId,
          _performanceEventReconnectSuccess,
          1,
        ),
      );

    _reportPerformanceTime(
      deviceId,
      _performanceEventReconnect,
      endTime.difference(startTime),
      startTime,
      endTime,
    );
  }

  Future<void> run() async {
    _setupCommunication();
    _registerDevices();
    _startConnections();

    // Keep isolate alive
    await Completer<void>().future;
  }

  void _setupCommunication() {
    // Pipe read to service isolate
    readCtrl.stream.listen(c2sPort.send);

    // Create S2C port for receiving device events from service and announce ready
    final s2cPort = ReceivePort(_modbusS2cPortName);
    c2sPort.send(ChannelReadyEvent(s2cPort.sendPort));

    // Filter and forward device events to write stream
    s2cPort.listen((msg) {
      if (msg is DeviceBaseEvent) writeCtrl.add(msg);
    });
  }

  void _registerDevices() {
    for (final device in devices) {
      try {
        _registerDevice(device);
      } on Object catch (error, stackTrace) {
        // Keep handler running regardless of individual device config errors
        print('Failed to register device ${device.deviceId}: $error');
        print('Stack trace: $stackTrace');
      }
    }
  }

  void _registerDevice(ChannelOptionGroup device) {
    final deviceId = device.deviceId;
    final ch = device.channel as ChannelOptionForModbus;
    final tp = device.template as ChannelTemplateForModbus;

    final key = _clientKey(ch);

    // Record device under connection key
    (connDevices[key] ??= <String>{}).add(deviceId);
    sessionSpecs[deviceId] = (channelOption: ch, templateOption: tp);

    // Store connection info for this key
    connectionInfos.putIfAbsent(
      key,
      () => (
        transport: ch.transport,
        isRtu: ch.isRtu,
        deviceIds: <String>{},
      ),
    );
    connectionInfos[key]!.deviceIds.add(deviceId);

    // Initial state: disconnected, report offline
    readCtrl.add(ChannelDeviceStatusEvent(deviceId, false));
  }

  void _startConnections() {
    for (final entry in connectionInfos.entries) {
      final config = _transportToConfig(entry.value.transport);
      tcpManager.addConnection(entry.key, config);
    }
  }

  /// Cleanup resources
  void dispose() {
    tcpManager.stop();
  }
}

/// New handler entry for isolate-based factory startup.
/// Accepts all devices using Modbus channel and a SendPort to send C2S events.
Future<void> modbusChannelFactoryHandler(
  List<ChannelOptionGroup> devices,
  SendPort c2sPort,
) async {
  final runner = _ModbusAdapterRunner(devices, c2sPort);
  await runner.run();
}
