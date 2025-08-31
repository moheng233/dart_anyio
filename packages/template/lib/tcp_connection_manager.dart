import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// TCP连接配置
class TcpConnectionConfig {
  const TcpConnectionConfig({
    required this.host,
    required this.port,
    this.isUnixSocket = false,
  });

  /// 从Unix socket路径创建配置
  factory TcpConnectionConfig.unix(String path) {
    return TcpConnectionConfig(
      host: path,
      port: 0,
      isUnixSocket: true,
    );
  }

  /// 从主机和端口创建TCP配置
  factory TcpConnectionConfig.tcp(String host, int port) {
    return TcpConnectionConfig(host: host, port: port);
  }

  final String host;
  final int port;
  final bool isUnixSocket;
}

/// TCP连接状态
enum TcpConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// TCP连接条目
class _ConnectionEntry {
  _ConnectionEntry({
    required this.state,
    required this.config,
  });

  TcpConnectionState state;
  Socket? socket;
  TcpConnectionConfig config;
  StreamSubscription<Socket>? socketMonitor;

  // 连接的数据流
  final StreamController<Uint8List> _dataController = StreamController<Uint8List>.broadcast();
  final StreamController<Uint8List> _writeController = StreamController<Uint8List>();

  Stream<Uint8List> get dataStream => _dataController.stream;
  StreamSink<Uint8List> get dataSink => _writeController.sink;

  void _connectToSocket(Socket socket) {
    // 监听socket数据
    socket.listen(
      (data) => _dataController.add(Uint8List.fromList(data)),
      onError: (error) => _dataController.addError(error),
      onDone: () => _dataController.close(),
    );

    // 监听写入请求并发送到socket
    _writeController.stream.listen(socket.add);
  }

  void _disconnect() {
    _dataController.close();
    _writeController.close();
  }
}

/// TCP连接管理器，负责TCP连接的建立、监控和自动重连
class TcpConnectionManager {
  TcpConnectionManager({
    required this.onConnectionStateChanged,
    required this.onConnectionEstablished,
    required this.onConnectionLost,
    this.maxReconnectAttempts = 10,
    this.initialReconnectDelay = const Duration(seconds: 1),
    this.maxReconnectDelay = const Duration(seconds: 30),
  });

  void Function(String connectionKey, TcpConnectionState state)
  onConnectionStateChanged;
  void Function(String connectionKey, Socket socket) onConnectionEstablished;
  void Function(String connectionKey, Object? error) onConnectionLost;

  final int maxReconnectAttempts;
  final Duration initialReconnectDelay;
  final Duration maxReconnectDelay;

  final Map<String, _ConnectionEntry> _connections = {};
  final Map<String, int> _reconnectAttempts = {};
  final Map<String, DateTime> _nextReconnectAt = {};
  final Set<String> _pendingReconnect = {};
  Timer? _reconnectTimer;

  static const Duration _reconnectCheckInterval = Duration(seconds: 1);

  /// 添加连接
  void addConnection(String connectionKey, TcpConnectionConfig config) {
    if (_connections.containsKey(connectionKey)) {
      return; // 连接已存在
    }

    _connections[connectionKey] = _ConnectionEntry(
      state: TcpConnectionState.disconnected,
      config: config,
    );

    // 立即尝试连接
    _enqueueReconnect(connectionKey);
  }

  /// 移除连接
  void removeConnection(String connectionKey) {
    final entry = _connections.remove(connectionKey);
    if (entry != null) {
      _cleanupConnection(entry);
    }

    _reconnectAttempts.remove(connectionKey);
    _nextReconnectAt.remove(connectionKey);
    _pendingReconnect.remove(connectionKey);
  }

  /// 获取连接状态
  TcpConnectionState getConnectionState(String connectionKey) {
    return _connections[connectionKey]?.state ??
        TcpConnectionState.disconnected;
  }

  /// 获取连接的socket
  Socket? getSocket(String connectionKey) {
    return _connections[connectionKey]?.socket;
  }

  /// 获取连接的数据流
  Stream<Uint8List> getDataStream(String connectionKey) {
    return _connections[connectionKey]?.dataStream ?? const Stream.empty();
  }

  /// 更新回调函数
  void updateCallbacks({
    void Function(String connectionKey, TcpConnectionState state)?
    onConnectionStateChanged,
    void Function(String connectionKey, Socket socket)? onConnectionEstablished,
    void Function(String connectionKey, Object? error)? onConnectionLost,
  }) {
    if (onConnectionStateChanged != null) {
      this.onConnectionStateChanged = onConnectionStateChanged;
    }
    if (onConnectionEstablished != null) {
      this.onConnectionEstablished = onConnectionEstablished;
    }
    if (onConnectionLost != null) {
      this.onConnectionLost = onConnectionLost;
    }
  }

  /// 停止所有连接
  void stop() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    for (final entry in _connections.values) {
      _cleanupConnection(entry);
    }

    _connections.clear();
    _reconnectAttempts.clear();
    _nextReconnectAt.clear();
    _pendingReconnect.clear();
  }

  /// 建立socket连接
  Future<Socket> _connectSocket(TcpConnectionConfig config) async {
    if (config.isUnixSocket) {
      return Socket.connect(
        InternetAddress(config.host, type: InternetAddressType.unix),
        0,
      );
    } else {
      return Socket.connect(
        InternetAddress(config.host, type: InternetAddressType.IPv4),
        config.port,
      );
    }
  }

  /// 启动socket监控
  void _startSocketMonitor(String connectionKey, Socket socket) {
    final subscription =
        socket.done.asStream().listen(
              (dynamic _) => _handleConnectionLost(connectionKey, null),
              onError: (Object error) =>
                  _handleConnectionLost(connectionKey, error),
            )
            as StreamSubscription<Socket>;

    final entry = _connections[connectionKey];
    if (entry != null) {
      entry.socketMonitor?.cancel(); // 取消之前的订阅
      entry.socketMonitor = subscription;
    } else {
      subscription.cancel(); // 如果entry不存在，立即取消订阅
    }
  }

  /// 处理连接丢失
  void _handleConnectionLost(String connectionKey, Object? error) {
    final entry = _connections[connectionKey];
    if (entry == null) return;

    // 清理连接
    _cleanupConnection(entry);

    // 更新状态
    entry
      ..state = TcpConnectionState.disconnected
      ..socket = null
      ..socketMonitor = null;

    // 通知连接丢失
    onConnectionLost(connectionKey, error);

    // 加入重连队列
    _enqueueReconnect(connectionKey);
  }

  /// 清理连接资源
  void _cleanupConnection(_ConnectionEntry entry) {
    entry.socketMonitor?.cancel();
    entry.socket?.destroy();
    entry._disconnect(); // 断开数据流
    // Note: ModbusClient may not have a close method, so we skip it
  }

  /// 加入重连队列
  void _enqueueReconnect(String connectionKey) {
    if (!_connections.containsKey(connectionKey)) return;

    _pendingReconnect.add(connectionKey);
    _nextReconnectAt.putIfAbsent(connectionKey, DateTime.now);
    _startReconnectTimer();
  }

  /// 启动重连定时器
  void _startReconnectTimer() {
    _reconnectTimer ??= Timer.periodic(
      _reconnectCheckInterval,
      (_) => _onReconnectTick(),
    );
  }

  /// 计算重连延迟
  Duration _calculateReconnectDelay(int attemptCount) {
    if (attemptCount <= 1) return initialReconnectDelay;
    if (attemptCount == 2) return const Duration(seconds: 2);
    if (attemptCount == 3) return const Duration(seconds: 5);
    if (attemptCount == 4) return const Duration(seconds: 10);

    return maxReconnectDelay;
  }

  /// 重连定时器回调
  void _onReconnectTick() {
    if (_pendingReconnect.isEmpty) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      return;
    }

    final now = DateTime.now();
    final keysToProcess = List<String>.from(_pendingReconnect);

    for (final connectionKey in keysToProcess) {
      final entry = _connections[connectionKey];
      if (entry == null) {
        _pendingReconnect.remove(connectionKey);
        _nextReconnectAt.remove(connectionKey);
        continue;
      }

      // 如果正在重连，跳过
      if (entry.state == TcpConnectionState.reconnecting) continue;

      final nextAttemptAt = _nextReconnectAt[connectionKey];
      if (nextAttemptAt != null && nextAttemptAt.isAfter(now)) continue;

      _attemptReconnect(connectionKey);
    }
  }

  /// 尝试重连
  Future<void> _attemptReconnect(String connectionKey) async {
    final entry = _connections[connectionKey];
    if (entry == null) return;

    final attemptCount = (_reconnectAttempts[connectionKey] ?? 0) + 1;

    // 检查是否超过最大重连次数
    if (attemptCount > maxReconnectAttempts) {
      _pendingReconnect.remove(connectionKey);
      _nextReconnectAt.remove(connectionKey);
      return;
    }

    // 更新状态为重连中
    entry.state = TcpConnectionState.reconnecting;
    entry.socket = null;
    entry.socketMonitor = null;

    onConnectionStateChanged(connectionKey, TcpConnectionState.reconnecting);

    try {
      // 建立socket连接
      final socket = await _connectSocket(entry.config);
      socket.setOption(SocketOption.tcpNoDelay, true);

      // 启动socket监控
      _startSocketMonitor(connectionKey, socket);

      // 更新连接状态
      entry.state = TcpConnectionState.connected;
      entry.socket = socket;

      // 重置重连计数
      _reconnectAttempts[connectionKey] = 0;
      _pendingReconnect.remove(connectionKey);
      _nextReconnectAt.remove(connectionKey);

      // 通知连接建立
      onConnectionStateChanged(connectionKey, TcpConnectionState.connected);
      onConnectionEstablished(connectionKey, socket);

      // 连接到数据流
      entry._connectToSocket(socket);
    } catch (error) {
      // 重连失败，更新重连计数和下次重连时间
      _reconnectAttempts[connectionKey] = attemptCount;
      _nextReconnectAt[connectionKey] = DateTime.now().add(
        _calculateReconnectDelay(attemptCount),
      );

      // 更新状态为断开连接
      entry.state = TcpConnectionState.disconnected;
      entry.socket = null;
      entry.socketMonitor = null;

      onConnectionStateChanged(connectionKey, TcpConnectionState.disconnected);
    }
  }
}
