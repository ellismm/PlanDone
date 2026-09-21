import '../../../domain/repositories/hierarchy_view_preferences_repository.dart';

class InMemoryHierarchyViewPreferencesRepository
    implements HierarchyViewPreferencesRepository {
  InMemoryHierarchyViewPreferencesRepository({required String userId});

  Set<String> _collapsedItemIds = <String>{};

  @override
  Future<Set<String>> loadCollapsedItemIds() async {
    return <String>{..._collapsedItemIds};
  }

  @override
  Future<Set<String>> saveCollapsedItemIds(Set<String> itemIds) async {
    final saved = <String>{...itemIds};
    _collapsedItemIds = saved;
    return <String>{...saved};
  }
}
