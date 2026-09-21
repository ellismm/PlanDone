abstract class HierarchyViewPreferencesRepository {
  Future<Set<String>> loadCollapsedItemIds();

  Future<Set<String>> saveCollapsedItemIds(Set<String> itemIds);
}
