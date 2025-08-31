import 'dart:collection';

import 'component.dart';
import 'query.dart';
import 'system.dart';

typedef Entity = int;

final class EcsWorld {
  factory EcsWorld(void Function(EcsWorldBuilder builder) exec) {
    final builder = EcsWorldBuilder();

    exec(builder);

    return EcsWorld._(
      components: builder._components,
      system: builder._system!,
    );
  }

  EcsWorld._({
    required Map<Type, ComponentOptions> components,
    required EcsSystem system,
  }) : assert(components.isNotEmpty, ''),
       _system = system,
       _componentOptions = HashMap.from(components) {
    for (final c in components.keys) {
      _components.putIfAbsent(c, HashMap.new);
    }
  }

  final _entitys = HashSet<Entity>();
  final HashMap<Type, ComponentOptions> _componentOptions;
  final _components = HashMap<Type, HashMap<Entity, Component>>();
  final EcsSystem _system;
  var _nextEntityId = 0;
  bool _isInitialized = false;

  /// Gets all entities in the world.
  Iterable<Entity> get allEntities => _entitys;

  /// Gets the total number of entities in the world.
  int get entityCount => _entitys.length;

  /// Adds a component to an entity.
  void addComponent<C extends Component>(Entity entity, C component) {
    assert(
      _entitys.contains(entity),
      'Entity $entity does not exist in the world.',
    );
    assert(
      _components.containsKey(C),
      'Component type $C is not registered in the ECS world. '
      'Make sure to include it in the components list when creating the world.',
    );

    _components[C]![entity] = component;
  }

  /// Creates a new entity and returns its ID.
  Entity createEntity([Iterable<Component>? components]) {
    final entity = _nextEntityId++;
    _entitys.add(entity);

    if (components != null) {
      for (final c in components) {
        addComponent(entity, c);
      }
    }

    return entity;
  }

  /// Destroys an entity and removes all its components.
  void destroyEntity(Entity entity) {
    if (!_entitys.contains(entity)) {
      return;
    }

    _entitys.remove(entity);

    // Remove entity from all component collections
    for (final componentMap in _components.values) {
      componentMap.remove(entity);
    }
  }

  /// Disposes of the world and cleans up resources.
  Future<void> dispose() async {
    if (_isInitialized) {
      // Destroy the system first
      await _system.onDestroy(this);
      _isInitialized = false;
    }
    _entitys.clear();
    _components.clear();
  }

  /// Gets a component from an entity.
  C? getComponent<C extends Component>(Entity entity) {
    assert(
      _entitys.contains(entity),
      'Entity $entity does not exist in the world.',
    );
    assert(
      _components.containsKey(C),
      'Component type $C is not registered in the ECS world.',
    );

    return _components[C]![entity] as C?;
  }

  bool hasComponent<C extends Component>(Entity entity) {
    assert(
      _components.containsKey(C),
      'Component type $C is not registered in the ECS world. '
      'Make sure to include it in the components list when creating the world.',
    );
    return _components[C]!.containsKey(entity);
  }

  bool hasEntity(Entity entity) {
    return _entitys.contains(entity);
  }

  /// Initializes the world asynchronously
  Future<void> initialize() async {
    if (!_isInitialized) {
      await _system.onInit(this);
      _isInitialized = true;
    }
  }

  /// Removes a component from an entity.
  void removeComponent<C extends Component>(Entity entity) {
    assert(
      _entitys.contains(entity),
      'Entity $entity does not exist in the world.',
    );
    assert(
      _components.containsKey(C),
      'Component type $C is not registered in the ECS world.',
    );

    _components[C]!.remove(entity);
  }

  /// Executes a query and returns matching entities.
  Iterable<Entity> startQuery(EcsQuery query) {
    return query.execute(this);
  }

  /// Updates the world by calling the system's update method.
  Future<void> update(Duration deltaTime) async {
    await _system.update(this, deltaTime);
  }
}

/// Builder class for constructing EcsWorld instances with a fluent interface.
class EcsWorldBuilder {
  final _components = <Type, ComponentOptions>{};
  EcsSystem? _system;

  /// Registers a component type with default options.
  void registerComponent<C extends Component>({bool exportCloud = false}) {
    return registerComponentWithOptions<C>(
      ComponentOptions(exportCloud: exportCloud),
    );
  }

  /// Registers a component type with custom options.
  void registerComponentWithOptions<C extends Component>(
    ComponentOptions options,
  ) {
    _components[C] = options;
  }

  /// Sets the system for the world.
  void withSystem(EcsSystem system) {
    _system = system;
  }

  /// Creates a copy of this builder with the same configuration.
  EcsWorldBuilder copy() {
    final copy = EcsWorldBuilder()
      .._components.addAll(_components)
      .._system = _system;
    return copy;
  }

  /// Clears all registered components and system.
  void clear() {
    _components.clear();
    _system = null;
  }

  /// Gets the number of registered component types.
  int get componentCount => _components.length;

  /// Checks if a component type is registered.
  bool isComponentRegistered<C extends Component>() {
    return _components.containsKey(C);
  }

  /// Gets the options for a registered component type.
  ComponentOptions? getComponentOptions<C extends Component>() {
    return _components[C];
  }
}
