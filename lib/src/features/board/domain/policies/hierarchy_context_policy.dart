import '../models/work_item.dart';

class HierarchyContextPolicy {
  const HierarchyContextPolicy._();

  static List<WorkItem> expandMatchedItems({
    required List<WorkItem> allItems,
    required List<WorkItem> matchedItems,
  }) {
    if (matchedItems.isEmpty) return const [];

    final itemsById = {
      for (final item in allItems) item.itemId: item,
    };
    final childrenByParent = <String?, List<WorkItem>>{};
    for (final item in allItems) {
      childrenByParent.putIfAbsent(item.parentId, () => []).add(item);
    }

    final includedIds = <String>{};
    final traversedDescendantParents = <String>{};

    void includeAncestors(WorkItem item) {
      var currentParentId = item.parentId;
      final visitedAncestorIds = <String>{};
      while (
          currentParentId != null && visitedAncestorIds.add(currentParentId)) {
        includedIds.add(currentParentId);
        currentParentId = itemsById[currentParentId]?.parentId;
      }
    }

    void includeDescendants(String parentId) {
      if (!traversedDescendantParents.add(parentId)) return;
      final children = childrenByParent[parentId] ?? const <WorkItem>[];
      for (final child in children) {
        includedIds.add(child.itemId);
        includeDescendants(child.itemId);
      }
    }

    for (final item in matchedItems) {
      includedIds.add(item.itemId);
      includeAncestors(item);
      includeDescendants(item.itemId);
    }

    return allItems
        .where((item) => includedIds.contains(item.itemId))
        .toList(growable: false);
  }

  static Set<String> findUnreachableItemIds({
    required List<WorkItem> items,
  }) {
    if (items.isEmpty) return const <String>{};

    final itemsById = {
      for (final item in items) item.itemId: item,
    };
    final childrenByParent = <String?, List<WorkItem>>{};
    for (final item in items) {
      final parentKey =
          itemsById.containsKey(item.parentId) ? item.parentId : null;
      childrenByParent.putIfAbsent(parentKey, () => []).add(item);
    }

    final reachable = <String>{};

    void visit(String? parentId, Set<String> activePath) {
      final children = childrenByParent[parentId] ?? const <WorkItem>[];
      for (final child in children) {
        if (!reachable.add(child.itemId)) continue;
        if (activePath.contains(child.itemId)) continue;
        visit(child.itemId, <String>{...activePath, child.itemId});
      }
    }

    visit(null, <String>{});

    return itemsById.keys
        .where((itemId) => !reachable.contains(itemId))
        .toSet();
  }
}
