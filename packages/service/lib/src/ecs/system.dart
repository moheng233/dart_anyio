import 'package:meta/meta.dart';

import 'world.dart';

/// Base interface for all ECS systems
@immutable
abstract interface class EcsSystem {
  /// Updates the system with the given world and delta time
  Future<void> update(EcsWorld world, Duration deltaTime);

  /// Called when the system is added to a world
  Future<void> onInit(EcsWorld world) async {}

  /// Called when the system is removed from a world
  Future<void> onDestroy(EcsWorld world) async {}
}

/// System container that can hold multiple systems
@immutable
abstract class SystemContainer implements EcsSystem {
  const SystemContainer(this.systems);

  final List<EcsSystem> systems;

  @override
  Future<void> onInit(EcsWorld world) async {
    for (final system in systems) {
      await system.onInit(world);
    }
  }

  @override
  Future<void> onDestroy(EcsWorld world) async {
    for (final system in systems) {
      await system.onDestroy(world);
    }
  }
}

/// Sequential system container - executes systems one after another
class SequentialSystem extends SystemContainer {
  const SequentialSystem(super.systems);

  @override
  Future<void> update(EcsWorld world, Duration deltaTime) async {
    for (final system in systems) {
      await system.update(world, deltaTime);
    }
  }
}

/// Parallel system container - executes systems concurrently
class ParallelSystem extends SystemContainer {
  const ParallelSystem(super.systems);

  @override
  Future<void> update(EcsWorld world, Duration deltaTime) async {
    if (systems.isEmpty) return;

    // Execute all systems in parallel
    final futures = <Future<void>>[];
    for (final system in systems) {
      futures.add(system.update(world, deltaTime));
    }

    // Wait for all systems to complete
    await Future.wait(futures);
  }
}

/// Conditional system - only executes when a condition is met
class ConditionalSystem implements EcsSystem {
  const ConditionalSystem(this.system, this.condition);

  final EcsSystem system;
  final bool Function(EcsWorld world) condition;

  @override
  Future<void> update(EcsWorld world, Duration deltaTime) async {
    if (condition(world)) {
      await system.update(world, deltaTime);
    }
  }

  @override
  Future<void> onInit(EcsWorld world) async {
    await system.onInit(world);
  }

  @override
  Future<void> onDestroy(EcsWorld world) async {
    await system.onDestroy(world);
  }
}

/// Component that stores interval execution state
class IntervalState {
  IntervalState(this.interval, {this.accumulator = Duration.zero});

  final Duration interval;
  Duration accumulator;

  bool shouldExecute(Duration deltaTime) {
    accumulator += deltaTime;
    if (accumulator >= interval) {
      accumulator -= interval;
      return true;
    }
    return false;
  }
}

/// System that executes at a fixed interval
class IntervalSystem implements EcsSystem {
  const IntervalSystem(this.system, this.interval);

  final EcsSystem system;
  final Duration interval;

  @override
  Future<void> update(EcsWorld world, Duration deltaTime) async {
    // For now, execute the system at every interval
    // In a real implementation, you'd want to track time per entity
    await system.update(world, interval);
  }

  @override
  Future<void> onInit(EcsWorld world) async {
    await system.onInit(world);
  }

  @override
  Future<void> onDestroy(EcsWorld world) async {
    await system.onDestroy(world);
  }
}
