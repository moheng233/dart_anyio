import 'component.dart';
import 'world.dart';

final class EcsQuery {
  EcsQuery(this.filters);

  EcsQuery.single(Filter filter) : this([filter]);

  EcsQuery.all(this.filters);

  final List<Filter> filters;

  /// Executes the query on the given world and returns matching entities.
  Iterable<Entity> execute(EcsWorld world) {
    if (filters.isEmpty) {
      return world.allEntities;
    }

    var result = world.allEntities;

    for (final filter in filters) {
      result = filter.match(world, result);
    }

    return result;
  }
}

abstract class Filter<T extends Component> {
  Filter()
    : assert(
        T != Component,
        'Filter type T must be concrete, not base Component class. '
        'Use specific types like Position or Velocity.',
      );

  /// Unique identifier.
  String get filterId;

  Type get type => T;

  /// Method for matching an [Entity] against this filter.
  Iterable<Entity> match(EcsWorld world, Iterable<Entity> iterable);
}

class Has<T extends Component> extends Filter<T> {
  @override
  String get filterId => 'Has<$T>';

  @override
  Iterable<Entity> match(EcsWorld world, Iterable<Entity> iterable) =>
      iterable.where(
        (element) => world.hasComponent<T>(element),
      );
}
