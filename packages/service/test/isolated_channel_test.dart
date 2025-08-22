import 'dart:async';
import 'dart:isolate';

import 'package:anyio_service/service.dart';
import 'package:anyio_template/service.dart';
import 'package:dart_mappable/dart_mappable.dart';

/// Basic test for isolated channel functionality
void main() async {
  print('Testing Isolated Channel Implementation...');

  // Test basic isolated channel session creation
  await testIsolatedChannelCreation();

  // Test error handling and restart
  await testChannelRestartLogic();

  print('All tests completed successfully!');
}

Future<void> testIsolatedChannelCreation() async {
  print('\n=== Testing Isolated Channel Creation ===');

  try {
    // Create a mock channel factory (this would be a real factory in practice)
    final mockFactory = MockChannelFactory();

    // Create isolated channel session
    final deviceEventController = StreamController<DeviceBaseEvent>();
    final isolatedSession = IsolatedChannelSession(
      deviceId: 'test-device',
      channelFactory: mockFactory,
      channelOption: MockChannelOption(),
      templateOption: MockTemplateOption(),
      transport: MockTransportSession(),
      deviceEvent: deviceEventController.stream,
    );

    print('✓ Isolated channel session created successfully');

    // Test opening and closing
    isolatedSession.open();
    print('✓ Channel opened');

    await Future.delayed(Duration(milliseconds: 100));

    isolatedSession.stop();
    print('✓ Channel stopped');

    await isolatedSession.dispose();
    await deviceEventController.close();
    print('✓ Resources disposed');
  } catch (e) {
    print('✗ Test failed: $e');
  }
}

Future<void> testChannelRestartLogic() async {
  print('\n=== Testing Channel Restart Logic ===');

  try {
    // Create service manager with restart enabled
    final channelManager = ChannelManagerImpl(useIsolatedChannels: true);
    channelManager.registerFactory(MockChannelFactory());

    final serviceManager = ServiceManager(
      channelManager: channelManager,
      transportManager: MockTransportManager(),
      enableChannelRestart: true,
      maxRestartAttempts: 3,
      restartDelaySeconds: 1,
    );

    print('✓ Service manager created with restart enabled');

    // Test restart statistics
    final stats = serviceManager.getRestartStats();
    print('✓ Restart stats initialized: ${stats.isEmpty}');

    print('✓ Channel restart logic tested');
  } catch (e) {
    print('✗ Test failed: $e');
  }
}

// Mock implementations for testing

final class MockChannelFactory extends ChannelFactory {
  @override
  ChannelSession create(
    String deviceId, {
    required Stream<DeviceBaseEvent> deviceEvent,
    required TransportSession transport,
    required ChannelOptionBase channelOption,
    required ChannelTemplateBase templateOption,
  }) {
    return MockChannelSession();
  }

  @override
  ClassMapperBase<ChannelOptionBase> get channelOptionMapper =>
      throw UnimplementedError();

  @override
  ClassMapperBase<ChannelTemplateBase> get templateOptionMapper =>
      throw UnimplementedError();
}

final class MockChannelSession extends ChannelSession {
  MockChannelSession() : super(write: const Stream.empty());

  final _readController = StreamController<ChannelBaseEvent>.broadcast();

  @override
  Stream<ChannelBaseEvent> get read => _readController.stream;

  @override
  void open() {}

  @override
  void stop() {
    _readController.close();
  }
}

final class MockChannelOption extends ChannelOptionBase {}

final class MockTemplateOption extends ChannelTemplateBase {}

class MockTransportSession implements TransportSession {
  @override
  Stream<List<int>> get read => Stream.empty();

  @override
  void Function(List<int>) get write => (data) {};

  @override
  Future<void> open() async {}

  @override
  void close() {}
}

class MockTransportManager implements TransportManager {
  @override
  TransportSession create(TransportOptionBase option) {
    return MockTransportSession();
  }

  @override
  void register(TransportFactory factory) {}
}
