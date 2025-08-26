import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:anyio_modbus/modbus_client.dart';
import 'package:anyio_template/service.dart';

import 'session.dart';
import 'template.dart';

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

class _ModbusAdapterRunner {
  _ModbusAdapterRunner(this.devices, this.c2sPort)
    : readCtrl = StreamController<ChannelBaseEvent>(sync: true),
      writeCtrl = StreamController<DeviceBaseEvent>.broadcast(sync: true);

  final List<ChannelOptionGroup> devices;
  final SendPort c2sPort;

  // Per-factory streams
  final StreamController<ChannelBaseEvent> readCtrl;
  final StreamController<DeviceBaseEvent> writeCtrl;

  // Pooling and session state
  final sessions = <String, ChannelSessionForModbus>{};
  final clients = <String, _ModbusClientEntry>{};
  final connDevices = <String, Set<String>>{}; // connectionKey -> deviceIds
  final reconnectAttempts = <String, int>{};
  final sessionSpecs = <String, _SessionSpec>{};
  final nextAttemptAt = <String, DateTime>{};
  final Set<String> pendingReconnect = <String>{};
  Timer? _reconnectTicker;
  static const Duration _tickInterval = Duration(seconds: 1);

  String _clientKey(ChannelOptionForModbus ch) {
    final t = ch.transport;
    if (t is ModbusTcpOption) return 'tcp:${t.host}:${t.port}';
    if (t is ModbusUnixSocketOption) return 'unix:${t.path}';
    return 'unknown';
  }

  Future<Socket> _connectSocket(ModbusTransportOption t) async {
    if (t is ModbusTcpOption) {
      return Socket.connect(
        InternetAddress(t.host, type: InternetAddressType.IPv4),
        t.port,
      );
    }
    if (t is ModbusUnixSocketOption) {
      return Socket.connect(
        InternetAddress(t.path, type: InternetAddressType.unix),
        0,
      );
    }
    throw UnsupportedError('Unsupported transport');
  }

  void _notifyConnectionDown(String key, Object? error) {
    final ids = connDevices[key];
    if (ids == null || ids.isEmpty) return;
    for (final id in ids) {
      sessions[id]?.stop();
      // 上报设备离线
      readCtrl.add(ChannelDeviceStatusEvent(id, false));
    }
  }

  void _wireSocketMonitor(Socket socket, String key) {
    unawaited(
      Future<void>(() async {
        try {
          await socket.done;
          _notifyConnectionDown(key, null);
        } on Object catch (e) {
          _notifyConnectionDown(key, e);
        }
        _enqueueReconnect(key);
      }),
    );
  }

  void _enqueueReconnect(String key) {
    pendingReconnect.add(key);
    nextAttemptAt.putIfAbsent(key, DateTime.now);
    _startTicker();
  }

  void _startTicker() {
    _reconnectTicker ??= Timer.periodic(
      _tickInterval,
      (_) => _onReconnectTick(),
    );
  }

  Duration _backoffDelay(int n) {
    if (n <= 1) return const Duration(seconds: 1);
    if (n == 2) return const Duration(seconds: 2);
    if (n == 3) return const Duration(seconds: 5);
    if (n == 4) return const Duration(seconds: 10);
    return const Duration(seconds: 30);
  }

  void _onReconnectTick() {
    if (pendingReconnect.isEmpty) return;
    final now = DateTime.now();
    final keys = List<String>.from(pendingReconnect);
    for (final key in keys) {
      final pooled = clients[key];
      if (pooled == null) {
        pendingReconnect.remove(key);
        nextAttemptAt.remove(key);
        continue;
      }
      if (pooled.reconnecting) continue;
      final nextAt = nextAttemptAt[key] ?? now;
      if (nextAt.isAfter(now)) continue;
      _attemptReconnect(key);
    }
    if (pendingReconnect.isEmpty && _reconnectTicker != null) {
      _reconnectTicker!.cancel();
      _reconnectTicker = null;
    }
  }

  Future<void> _attemptReconnect(String key) async {
    final pooled = clients[key];
    if (pooled == null) return;
    clients[key] = (
      client: pooled.client,
      refCount: pooled.refCount,
      socket: pooled.socket,
      transport: pooled.transport,
      isRtu: pooled.isRtu,
      reconnecting: true,
    );

    final start = DateTime.now();
    try {
      // Report reconnect attempt count
      final attemptNo = (reconnectAttempts[key] ?? 0) + 1;
      final attemptIds = connDevices[key] ?? const <String>{};
      for (final id in attemptIds) {
        readCtrl.add(
          ChannelPerformanceCountEvent(id, 'conn.reconnect.attempt', attemptNo),
        );
      }

      final transport = clients[key]?.transport;
      final isRtu = clients[key]?.isRtu ?? false;
      if (transport == null) return;

      final socket = await _connectSocket(transport);
      final client = ModbusClient(socket, socket, isRtu: isRtu);

      _wireSocketMonitor(socket, key);

      final cur = clients[key];
      if (cur == null) return;
      clients[key] = (
        client: client,
        refCount: cur.refCount,
        socket: socket,
        transport: cur.transport,
        isRtu: cur.isRtu,
        reconnecting: false,
      );

      final ids = connDevices[key] ?? const <String>{};
      for (final id in ids) {
        final old = sessions[id];
        if (old != null) {
          old.stop();
        }
        final spec = sessionSpecs[id];
        if (spec == null) continue;
        final session = ChannelSessionForModbus(
          id,
          write: writeCtrl.stream.where(
            (e) => e is DeviceActionInvokeEvent && e.deviceId == id,
          ),
          client: client,
          channelOption: spec.channelOption,
          templateOption: spec.templateOption,
        );
        sessions[id] = session;
        session.read.listen(readCtrl.add);
        session.open();

        // 上报设备恢复在线
        readCtrl.add(ChannelDeviceStatusEvent(id, true));

        // Report reconnect success
        readCtrl.add(
          ChannelPerformanceCountEvent(id, 'conn.reconnect.success', 1),
        );

        final end = DateTime.now();
        readCtrl.add(
          ChannelPerformanceTimeEvent(
            id,
            'conn.reconnect',
            diffTime: end.difference(start),
            startTime: start,
            endTime: end,
          ),
        );
      }

      reconnectAttempts[key] = 0;
      pendingReconnect.remove(key);
      nextAttemptAt.remove(key);
    } on Exception {
      final n = (reconnectAttempts[key] ?? 0) + 1;
      reconnectAttempts[key] = n;
      final ids = connDevices[key] ?? const <String>{};
      for (final id in ids) {
        readCtrl.add(
          ChannelPerformanceCountEvent(id, 'conn.reconnect.fail', 1),
        );
      }
      pendingReconnect.add(key);
      nextAttemptAt[key] = DateTime.now().add(_backoffDelay(n));
      final cur = clients[key];
      if (cur != null) {
        clients[key] = (
          client: cur.client,
          refCount: cur.refCount,
          socket: cur.socket,
          transport: cur.transport,
          isRtu: cur.isRtu,
          reconnecting: false,
        );
      }
    }
  }

  Future<void> run() async {
    // Pipe read to service isolate
    readCtrl.stream.listen(c2sPort.send);

    // Create S2C port for receiving device events from service and announce ready
    final s2cPort = ReceivePort('modbus_s2c');
    c2sPort.send(ChannelReadyEvent(s2cPort.sendPort));
    // We filter only DeviceBaseEvent into write stream; a direct tearoff would
    // lose this filtering, so keep the small closure intentionally.
    // ignore: unnecessary_lambdas
    s2cPort.listen((msg) {
      if (msg is DeviceBaseEvent) writeCtrl.add(msg);
    });

    // Register all devices by connection key and schedule connection attempts
    for (final d in devices) {
      final deviceId = d.deviceId;
      try {
        final ch = d.channel as ChannelOptionForModbus;
        final tp = d.template as ChannelTemplateForModbus;

        final key = _clientKey(ch);
        // Record device under connection key
        (connDevices[key] ??= <String>{}).add(deviceId);
        sessionSpecs[deviceId] = (channelOption: ch, templateOption: tp);

        if (clients.containsKey(key)) {
          // Increase ref count for existing pooled client
          final cur = clients[key]!;
          clients[key] = (
            client: cur.client,
            refCount: cur.refCount + 1,
            socket: cur.socket,
            transport: cur.transport,
            isRtu: cur.isRtu,
            reconnecting: cur.reconnecting,
          );
        } else {
          // Create placeholder entry (no socket/client yet) and enqueue reconnect
          clients[key] = (
            client: null,
            refCount: 1,
            socket: null,
            transport: ch.transport,
            isRtu: ch.isRtu,
            reconnecting: false,
          );
          _enqueueReconnect(key);
        }

        // 初始状态：未连接，标记离线（直到首次连接成功时上报在线）
        readCtrl.add(ChannelDeviceStatusEvent(deviceId, false));
      } on Exception catch (_) {
        // Keep handler running regardless of individual device config errors.
      }
    }

    // keep isolate alive
    await Completer<void>().future;
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
