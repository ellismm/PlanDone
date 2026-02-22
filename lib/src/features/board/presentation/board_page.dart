import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/plan_done_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../domain/models/column.dart';
import '../domain/models/work_item.dart';
import '../domain/models/work_item_type.dart';
import 'board_controller.dart';

class BoardPage extends ConsumerWidget {
  const BoardPage({super.key});

  Future<String?> _pickTargetColumnForBoard(
    BuildContext context,
    WidgetRef ref, {
    required String boardId,
  }) async {
    final targetSnapshot = await ref.read(localBoardStoreProvider).getBoard(boardId);
    final ordered = [...targetSnapshot.columns]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    if (ordered.isEmpty) return null;

    if (!context.mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose target column'),
        children: [
          for (final column in ordered)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(column.columnId),
              child: Text(column.name),
            ),
        ],
      ),
    );
  }

  Future<void> _handleDropToBoardTarget(
    BuildContext context,
    WidgetRef ref, {
    required WorkItem item,
    required String targetBoardId,
  }) async {
    final targetColumnId = await _pickTargetColumnForBoard(context, ref, boardId: targetBoardId);
    if (targetColumnId == null) return;

    final sourceBoardId = item.boardId;
    final sourceColumnId = item.columnId;

    await ref.read(boardControllerProvider).moveItemToBoard(
          itemId: item.itemId,
          toBoardId: targetBoardId,
          toColumnId: targetColumnId,
        );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Item moved to another board'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            ref.read(boardControllerProvider).moveItemToBoard(
                  itemId: item.itemId,
                  toBoardId: sourceBoardId,
                  toColumnId: sourceColumnId,
                );
          },
        ),
      ),
    );
  }

  String _filterLabel(BoardVisibilityFilter filter) {
    return switch (filter) {
      BoardVisibilityFilter.tasksOnly => 'Tasks (containers)',
      BoardVisibilityFilter.goalsOnly => 'Goals',
      BoardVisibilityFilter.projectsOnly => 'Projects',
      BoardVisibilityFilter.actionsOnly => 'Action (doable)',
      BoardVisibilityFilter.allItems => 'All',
    };
  }

  bool _matchesFilter(WorkItem item, BoardVisibilityFilter filter) {
    return switch (filter) {
      BoardVisibilityFilter.tasksOnly => item.type == WorkItemType.task,
      BoardVisibilityFilter.goalsOnly => item.type == WorkItemType.goal,
      BoardVisibilityFilter.projectsOnly => item.type == WorkItemType.project,
      BoardVisibilityFilter.actionsOnly => item.type == WorkItemType.action,
      BoardVisibilityFilter.allItems => true,
    };
  }

  int _typeRank(WorkItemType type) {
    return switch (type) {
      WorkItemType.goal => 0,
      WorkItemType.project => 1,
      WorkItemType.task => 2,
      WorkItemType.action => 3,
    };
  }

  bool _isRecommendedParentType({
    required WorkItemType child,
    required WorkItemType parent,
  }) {
    return _typeRank(parent) < _typeRank(child);
  }

  Set<String> _focusRelatedItemIds(List<WorkItem> items, String focusedItemId) {
    final byId = {for (final item in items) item.itemId: item};
    final childMap = <String, List<WorkItem>>{};
    for (final item in items) {
      final parentId = item.parentId;
      if (parentId == null) continue;
      childMap.putIfAbsent(parentId, () => []).add(item);
    }

    final visible = <String>{focusedItemId};

    var cursor = byId[focusedItemId];
    while (cursor?.parentId != null) {
      final parent = byId[cursor!.parentId!];
      if (parent == null) break;
      visible.add(parent.itemId);
      cursor = parent;
    }

    final queue = <String>[focusedItemId];
    while (queue.isNotEmpty) {
      final id = queue.removeLast();
      final children = childMap[id] ?? const [];
      for (final child in children) {
        if (visible.add(child.itemId)) {
          queue.add(child.itemId);
        }
      }
    }

    return visible;
  }

  bool _isVisibleInCurrentModes({
    required WorkItem item,
    required BoardVisibilityFilter filter,
    required bool focusModeEnabled,
    required Set<String>? focusRelatedItemIds,
    required String textQuery,
    required bool showOverdueOnly,
    required bool showDueSoonOnly,
    required bool showArchivedOnly,
  }) {
    if (!_matchesFilter(item, filter)) return false;
    if (textQuery.trim().isNotEmpty && !item.title.toLowerCase().contains(textQuery.trim().toLowerCase())) {
      return false;
    }
    if (showOverdueOnly) {
      final dueAt = item.dueAt;
      final isOverdue = dueAt != null && item.completedAt == null && dueAt.isBefore(DateTime.now());
      if (!isOverdue) return false;
    }
    if (showDueSoonOnly) {
      final dueAt = item.dueAt;
      final now = DateTime.now();
      final horizon = now.add(const Duration(days: 7));
      final isDueSoon = dueAt != null && item.completedAt == null && !dueAt.isBefore(now) && !dueAt.isAfter(horizon);
      if (!isDueSoon) return false;
    }
    if (showArchivedOnly) {
      if (!item.archived) return false;
    } else if (item.archived) {
      return false;
    }
    if (!focusModeEnabled || focusRelatedItemIds == null) return true;
    return focusRelatedItemIds.contains(item.itemId);
  }

  List<WorkItem> _sortedVisibleItems({
    required List<WorkItem> items,
    required String columnId,
    required BoardVisibilityFilter filter,
    required bool focusModeEnabled,
    required Set<String>? focusRelatedItemIds,
    required String textQuery,
    required bool showOverdueOnly,
    required bool showDueSoonOnly,
    required bool showArchivedOnly,
  }) {
    final visible = items.where((i) {
      if (i.columnId != columnId) return false;
      return _isVisibleInCurrentModes(
        item: i,
        filter: filter,
        focusModeEnabled: focusModeEnabled,
        focusRelatedItemIds: focusRelatedItemIds,
        textQuery: textQuery,
        showOverdueOnly: showOverdueOnly,
        showDueSoonOnly: showDueSoonOnly,
        showArchivedOnly: showArchivedOnly,
      );
    }).toList();

    int urgencyRank(WorkItem item) {
      final now = DateTime.now();
      if (item.completedAt != null) return 3;
      if (item.dueAt != null && item.dueAt!.isBefore(now)) return 0;
      if (item.dueAt != null) return 1;
      return 2;
    }

    visible.sort((a, b) {
      final urgency = urgencyRank(a).compareTo(urgencyRank(b));
      if (urgency != 0) return urgency;

      if (a.dueAt != null && b.dueAt != null) {
        final due = a.dueAt!.compareTo(b.dueAt!);
        if (due != 0) return due;
      }

      final updated = b.updatedAt.compareTo(a.updatedAt);
      if (updated != 0) return updated;

      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return visible;
  }

  Future<void> _confirmDeleteColumn(
    BuildContext context,
    WidgetRef ref, {
    required String columnId,
    required String name,
    required bool canDelete,
  }) async {
    if (!canDelete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must keep at least one column.')),
      );
      return;
    }

    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete column?'),
            content: Text('Delete "$name"? Items will be moved to another column.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
            ],
          ),
        ) ??
        false;

    if (!shouldDelete) return;
    await ref.read(boardControllerProvider).deleteColumn(columnId);
  }

  Future<void> _showAddColumnDialog(BuildContext context, WidgetRef ref) async {
    String columnName = '';

    final submittedName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add column'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Column name'),
            textInputAction: TextInputAction.done,
            onChanged: (value) => columnName = value,
            onSubmitted: (value) {
              final name = value.trim();
              if (name.isEmpty) return;
              Navigator.of(context).pop(name);
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final name = columnName.trim();
                if (name.isEmpty) return;
                Navigator.of(context).pop(name);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    final name = submittedName?.trim();
    if (name == null || name.isEmpty) return;
    await ref.read(boardControllerProvider).createColumn(name);
  }

  Future<void> _showRenameColumnDialog(
    BuildContext context,
    WidgetRef ref, {
    required String columnId,
    required String currentName,
  }) async {
    String columnName = currentName;

    final submittedName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename column'),
          content: TextField(
            autofocus: true,
            decoration: InputDecoration(hintText: currentName),
            textInputAction: TextInputAction.done,
            onChanged: (value) => columnName = value,
            onSubmitted: (value) {
              final name = value.trim();
              if (name.isEmpty) return;
              Navigator.of(context).pop(name);
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final name = columnName.trim();
                if (name.isEmpty) return;
                Navigator.of(context).pop(name);
              },
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );

    final name = submittedName?.trim();
    if (name == null || name.isEmpty) return;
    await ref.read(boardControllerProvider).renameColumn(columnId: columnId, name: name);
  }

  Future<void> _showCreateBoardDialog(BuildContext context, WidgetRef ref) async {
    String boardName = '';

    final submittedName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create board'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Board name'),
            textInputAction: TextInputAction.done,
            onChanged: (value) => boardName = value,
            onSubmitted: (value) {
              final name = value.trim();
              if (name.isEmpty) return;
              Navigator.of(context).pop(name);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = boardName.trim();
                if (name.isEmpty) return;
                Navigator.of(context).pop(name);
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    final name = submittedName?.trim();
    if (name == null || name.isEmpty) return;

    await ref.read(boardControllerProvider).createBoard(name);
  }

  Future<void> _showAddTaskDialog(BuildContext context, WidgetRef ref) async {
    final snapshot = ref.read(boardStreamProvider).valueOrNull;
    if (snapshot == null) return;
    final columns = [...snapshot.columns]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    if (columns.isEmpty) return;

    String itemTitle = '';
    WorkItemType selectedType = WorkItemType.action;
    String selectedColumnId = columns.first.columnId;
    String? selectedParentId;
    final parentCandidates = [...snapshot.items]
      ..sort((a, b) {
        final byType = _typeRank(a.type).compareTo(_typeRank(b.type));
        if (byType != 0) return byType;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });

    final submitted = await showDialog<(String, WorkItemType, String, String?)>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Add item'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'Title'),
                    textInputAction: TextInputAction.done,
                    onChanged: (value) => itemTitle = value,
                    onSubmitted: (value) {
                      final title = value.trim();
                      if (title.isEmpty) return;
                      Navigator.of(context).pop((title, selectedType, selectedColumnId, selectedParentId));
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<WorkItemType>(
                    initialValue: selectedType,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(value: WorkItemType.goal, child: Text('Goal')),
                      DropdownMenuItem(value: WorkItemType.project, child: Text('Project')),
                      DropdownMenuItem(value: WorkItemType.task, child: Text('Task (container)')),
                      DropdownMenuItem(value: WorkItemType.action, child: Text('Action (doable)')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => selectedType = value);
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Action = directly doable work. Task is a planning container.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedColumnId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Column'),
                    items: [
                      for (final column in columns)
                        DropdownMenuItem(value: column.columnId, child: Text(column.name)),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => selectedColumnId = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: selectedParentId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Parent (optional)'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('None')),
                      for (final item in parentCandidates)
                        DropdownMenuItem<String?>(
                          value: item.itemId,
                          child: Text(
                            '${item.type.name.toUpperCase()}: ${item.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() => selectedParentId = value);
                    },
                  ),
                  if (selectedParentId != null)
                    Builder(
                      builder: (_) {
                        final parent = parentCandidates.where((x) => x.itemId == selectedParentId).cast<WorkItem?>().firstWhere(
                              (_) => true,
                              orElse: () => null,
                            );
                        if (parent == null) return const SizedBox.shrink();
                        final recommended = _isRecommendedParentType(
                          child: selectedType,
                          parent: parent.type,
                        );
                        if (recommended) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Tip: ${selectedType.name.toUpperCase()} items are usually nested under a higher-level type.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.orange.shade700,
                                ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final title = itemTitle.trim();
                    if (title.isEmpty) return;
                    Navigator.of(context).pop((title, selectedType, selectedColumnId, selectedParentId));
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (submitted == null) return;
    await ref.read(boardControllerProvider).createItem(
          title: submitted.$1,
          type: submitted.$2,
          toColumnId: submitted.$3,
          parentId: submitted.$4,
        );
  }

  Future<void> _showOutboxSheet(BuildContext context, WidgetRef ref) async {
    final pending = await ref.read(outboxQueueProvider).listPending();
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pending sync operations (${pending.length})', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                if (pending.isEmpty)
                  const Text('No pending operations')
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: pending.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final op = pending[index];
                        return ListTile(
                          dense: true,
                          title: Text('${op.type.name.toUpperCase()} ${op.entity}'),
                          subtitle: Text(op.entityId),
                          trailing: Text(
                            op.createdAt.toIso8601String().substring(11, 19),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showQuickAddChildActionDialog(
    BuildContext context,
    WidgetRef ref, {
    required WorkItem parent,
    required List<BoardColumn> columns,
  }) async {
    if (columns.isEmpty) return;

    String itemTitle = '';
    var selectedColumnId = parent.columnId;

    final submitted = await showDialog<(String, String)>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Add child action'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Parent: ${parent.title}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Action title',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => itemTitle = value,
                    onSubmitted: (value) {
                      final title = value.trim();
                      if (title.isEmpty) return;
                      Navigator.of(context).pop((title, selectedColumnId));
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedColumnId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Column'),
                    items: [
                      for (final column in columns)
                        DropdownMenuItem(
                          value: column.columnId,
                          child: Text(column.name),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => selectedColumnId = value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final title = itemTitle.trim();
                    if (title.isEmpty) return;
                    Navigator.of(context).pop((title, selectedColumnId));
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (submitted == null) return;
    await ref.read(boardControllerProvider).createItem(
          title: submitted.$1,
          type: WorkItemType.action,
          toColumnId: submitted.$2,
          parentId: parent.itemId,
        );
  }

  String _dateOnly(DateTime date) => date.toIso8601String().split('T').first;

  Future<void> _showEditItemSheet(
    BuildContext context,
    WidgetRef ref, {
    required WorkItem item,
    required List<WorkItem> allItems,
  }) async {
    final parentCandidates = allItems.where((x) => x.itemId != item.itemId).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    var title = item.title;
    var description = item.description ?? '';
    DateTime? selectedDueAt = item.dueAt;
    var tagsText = item.tags.join(', ');
    String? selectedParentId = item.parentId;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Edit item', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: title,
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => title = value,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: description,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => description = value,
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Due date',
                          border: OutlineInputBorder(),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                selectedDueAt == null ? 'No due date' : _dateOnly(selectedDueAt!),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Pick due date',
                              onPressed: () async {
                                final now = DateTime.now();
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: selectedDueAt ?? now,
                                  firstDate: DateTime(now.year - 10),
                                  lastDate: DateTime(now.year + 20),
                                );
                                if (picked != null) {
                                  setState(() => selectedDueAt = picked);
                                }
                              },
                              icon: const Icon(Icons.calendar_today),
                            ),
                            IconButton(
                              tooltip: 'Clear due date',
                              onPressed: selectedDueAt == null ? null : () => setState(() => selectedDueAt = null),
                              icon: const Icon(Icons.clear),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        initialValue: selectedParentId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Parent',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('None')),
                          for (final candidate in parentCandidates)
                            DropdownMenuItem<String?>(
                              value: candidate.itemId,
                              child: Text(
                                candidate.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() => selectedParentId = value),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: tagsText,
                        decoration: const InputDecoration(
                          labelText: 'Tags (comma separated)',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => tagsText = value,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () async {
                              final normalizedTitle = title.trim();
                              if (normalizedTitle.isEmpty) return;

                              final normalizedDescription = description.trim();
                              final dueAt = selectedDueAt;
                              final clearDueAt = selectedDueAt == null;

                              final tags = tagsText
                                  .split(',')
                                  .map((t) => t.trim())
                                  .where((t) => t.isNotEmpty)
                                  .toList();

                              await ref.read(boardControllerProvider).updateItem(
                                    itemId: item.itemId,
                                    title: normalizedTitle,
                                    description: normalizedDescription.isEmpty ? null : normalizedDescription,
                                    clearDescription: normalizedDescription.isEmpty,
                                    parentId: selectedParentId,
                                    clearParent: selectedParentId == null,
                                    dueAt: dueAt,
                                    clearDueAt: clearDueAt,
                                    tags: tags,
                                  );
                              if (context.mounted) Navigator.of(context).pop();
                            },
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardAsync = ref.watch(boardStreamProvider);
    final boardsAsync = ref.watch(boardsProvider);
    final currentBoardId = ref.watch(currentBoardIdProvider);
    final visibilityFilter = ref.watch(boardVisibilityFilterProvider);
    final focusedItemId = ref.watch(focusedItemIdProvider);
    final focusModeEnabled = ref.watch(focusModeEnabledProvider);
    final textQuery = ref.watch(boardTextQueryProvider);
    final showOverdueOnly = ref.watch(showOverdueOnlyProvider);
    final showDueSoonOnly = ref.watch(showDueSoonOnlyProvider);
    final showArchivedOnly = ref.watch(showArchivedOnlyProvider);
    final pendingOutboxCountAsync = ref.watch(pendingOutboxCountProvider);
    final pendingCount = pendingOutboxCountAsync.valueOrNull ?? 0;
    final activeDraggedItem = ref.watch(activeDraggedItemProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PlanDone'),
        actions: [
          PopupMenuButton<PlanDoneThemeKey>(
            tooltip: 'Theme',
            onSelected: (value) {
              ref.read(themeControllerProvider.notifier).setTheme(value);
            },
            itemBuilder: (_) {
              final activeTheme = ref.watch(themeControllerProvider).valueOrNull ?? PlanDoneThemeKey.calmFocus;
              return [
                for (final theme in PlanDoneThemeKey.values)
                  PopupMenuItem(
                    value: theme,
                    child: Row(
                      children: [
                        if (theme == activeTheme)
                          const Icon(Icons.check, size: 16)
                        else
                          const SizedBox(width: 16),
                        const SizedBox(width: 8),
                        Text(PlanDoneThemes.label(theme)),
                      ],
                    ),
                  ),
              ];
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.palette_outlined),
            ),
          ),
          PopupMenuButton<BoardVisibilityFilter>(
            tooltip: 'Filter items',
            onSelected: (value) {
              ref.read(boardVisibilityFilterProvider.notifier).state = value;
            },
            itemBuilder: (_) => [
              for (final filter in BoardVisibilityFilter.values)
                PopupMenuItem(
                  value: filter,
                  child: Row(
                    children: [
                      if (filter == visibilityFilter)
                        const Icon(Icons.check, size: 16)
                      else
                        const SizedBox(width: 16),
                      const SizedBox(width: 8),
                      Text(_filterLabel(filter)),
                    ],
                  ),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  _filterLabel(visibilityFilter),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
          ),
          if (focusedItemId != null)
            IconButton(
              tooltip: 'Clear focus',
              onPressed: () {
                ref.read(focusedItemIdProvider.notifier).state = null;
                ref.read(focusModeEnabledProvider.notifier).state = false;
              },
              icon: const Icon(Icons.center_focus_weak),
            ),
          IconButton(
            tooltip: 'Toggle focus mode',
            onPressed: focusedItemId == null
                ? null
                : () {
                    final notifier = ref.read(focusModeEnabledProvider.notifier);
                    notifier.state = !notifier.state;
                  },
            icon: Icon(focusModeEnabled ? Icons.filter_center_focus : Icons.filter_center_focus_outlined),
          ),
          IconButton(
            tooltip: 'Pending sync operations',
            onPressed: () => _showOutboxSheet(context, ref),
            icon: Badge(
              isLabelVisible: pendingCount > 0,
              label: Text('$pendingCount'),
              child: const Icon(Icons.sync),
            ),
          ),
          IconButton(
            tooltip: 'Sync now',
            onPressed: () async {
              final report = await ref.read(boardControllerProvider).syncNow();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Sync complete: ${report.processed} processed, ${report.failed} failed',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.cloud_upload_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddTaskDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add Item'),
      ),
      body: boardAsync.when(
        data: (snapshot) {
          final boards = boardsAsync.valueOrNull ?? const [];
          final columns = [...snapshot.columns]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
          final focusRelatedItemIds = focusedItemId == null
              ? null
              : _focusRelatedItemIds(snapshot.items, focusedItemId);
          final screenWidth = MediaQuery.sizeOf(context).width;
          final columnWidth = screenWidth < 900 ? (screenWidth * 0.82).clamp(260.0, 360.0) : 320.0;

          return Column(
            children: [
              SizedBox(
                height: activeDraggedItem == null ? 60 : 86,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  children: [
                    for (final board in boards)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: DragTarget<WorkItem>(
                          onWillAcceptWithDetails: (details) {
                            return details.data.boardId != board.boardId;
                          },
                          onAcceptWithDetails: (details) {
                            _handleDropToBoardTarget(
                              context,
                              ref,
                              item: details.data,
                              targetBoardId: board.boardId,
                            );
                          },
                          builder: (context, candidateData, rejectedData) {
                            final isDropActive = candidateData.any(
                              (it) => it != null && it.boardId != board.boardId,
                            );
                            return ChoiceChip(
                              label: Text(board.name),
                              selected: board.boardId == currentBoardId,
                              onSelected: (_) {
                                ref.read(boardControllerProvider).switchBoard(board.boardId);
                              },
                              avatar: isDropActive
                                  ? const Icon(Icons.move_down, size: 16)
                                  : (activeDraggedItem != null
                                      ? const Icon(Icons.inbox_outlined, size: 16)
                                      : null),
                              padding: EdgeInsets.symmetric(
                                horizontal: activeDraggedItem != null ? 14 : 8,
                                vertical: activeDraggedItem != null ? 10 : 6,
                              ),
                              labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                            );
                          },
                        ),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: const Text('New board'),
                      onPressed: () => _showCreateBoardDialog(context, ref),
                    ),
                    const SizedBox(width: 8),
                    ActionChip(
                      avatar: const Icon(Icons.view_column, size: 18),
                      label: const Text('Add column'),
                      onPressed: () => _showAddColumnDialog(context, ref),
                    ),
                  ],
                ),
              ),
              if (activeDraggedItem != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
                  child: SizedBox(
                    height: 62,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final column in columns)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: DragTarget<WorkItem>(
                              onWillAcceptWithDetails: (details) {
                                return details.data.boardId == currentBoardId &&
                                    details.data.columnId != column.columnId;
                              },
                              onAcceptWithDetails: (details) {
                                ref.read(boardControllerProvider).moveItem(
                                      itemId: details.data.itemId,
                                      toColumnId: column.columnId,
                                    );
                              },
                              builder: (context, candidateData, rejectedData) {
                                final isDropActive = candidateData.any(
                                  (it) =>
                                      it != null &&
                                      it.boardId == currentBoardId &&
                                      it.columnId != column.columnId,
                                );
                                return Chip(
                                  avatar: Icon(
                                    isDropActive ? Icons.move_down : Icons.drag_indicator,
                                    size: 20,
                                  ),
                                  label: Text(
                                    column.name,
                                    style: Theme.of(context).textTheme.titleSmall,
                                  ),
                                  backgroundColor: isDropActive
                                      ? Theme.of(context).colorScheme.primaryContainer
                                      : null,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                                  side: BorderSide(
                                    color: isDropActive
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.outlineVariant,
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: textQuery,
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search items by title',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          ref.read(boardTextQueryProvider.notifier).state = value;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Overdue'),
                      selected: showOverdueOnly,
                      onSelected: (value) {
                        ref.read(showOverdueOnlyProvider.notifier).state = value;
                        if (value) {
                          ref.read(showDueSoonOnlyProvider.notifier).state = false;
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Due ≤ 7d'),
                      selected: showDueSoonOnly,
                      onSelected: (value) {
                        ref.read(showDueSoonOnlyProvider.notifier).state = value;
                        if (value) {
                          ref.read(showOverdueOnlyProvider.notifier).state = false;
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Archived'),
                      selected: showArchivedOnly,
                      onSelected: (value) {
                        ref.read(showArchivedOnlyProvider.notifier).state = value;
                      },
                    ),
                  ],
                ),
              ),
              if (focusModeEnabled && focusedItemId != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                  child: Text(
                    'Focus mode: showing selected item context (ancestors + descendants)',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    SizedBox(
                      width: 36,
                      child: Column(
                        children: [
                          IconButton(
                            tooltip: 'Move first column right',
                            onPressed: columns.length > 1
                                ? () {
                                    final ordered = [for (final c in columns) c.columnId];
                                    final first = ordered.removeAt(0);
                                    ordered.insert(1, first);
                                    ref.read(boardControllerProvider).reorderColumns(ordered);
                                  }
                                : null,
                            icon: const Icon(Icons.arrow_forward),
                          ),
                        ],
                      ),
                    ),
                    for (final column in columns)
                      SizedBox(
                        width: columnWidth,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(column.name, style: Theme.of(context).textTheme.titleMedium),
                                      ),
                                      IconButton(
                                        tooltip: 'Rename column',
                                        onPressed: () => _showRenameColumnDialog(
                                          context,
                                          ref,
                                          columnId: column.columnId,
                                          currentName: column.name,
                                        ),
                                        icon: const Icon(Icons.edit, size: 18),
                                      ),
                                      IconButton(
                                        tooltip: 'Move left',
                                        onPressed: () {
                                          final index = columns.indexWhere((c) => c.columnId == column.columnId);
                                          if (index <= 0) return;
                                          final ordered = [for (final c in columns) c.columnId];
                                          final id = ordered.removeAt(index);
                                          ordered.insert(index - 1, id);
                                          ref.read(boardControllerProvider).reorderColumns(ordered);
                                        },
                                        icon: const Icon(Icons.chevron_left),
                                      ),
                                      IconButton(
                                        tooltip: 'Move right',
                                        onPressed: () {
                                          final index = columns.indexWhere((c) => c.columnId == column.columnId);
                                          if (index < 0 || index >= columns.length - 1) return;
                                          final ordered = [for (final c in columns) c.columnId];
                                          final id = ordered.removeAt(index);
                                          ordered.insert(index + 1, id);
                                          ref.read(boardControllerProvider).reorderColumns(ordered);
                                        },
                                        icon: const Icon(Icons.chevron_right),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete column',
                                        onPressed: () => _confirmDeleteColumn(
                                          context,
                                          ref,
                                          columnId: column.columnId,
                                          name: column.name,
                                          canDelete: columns.length > 1,
                                        ),
                                        icon: const Icon(Icons.delete_outline, size: 18),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Builder(
                                    builder: (_) {
                                      final visibleItems = _sortedVisibleItems(
                                        items: snapshot.items,
                                        columnId: column.columnId,
                                        filter: visibilityFilter,
                                        focusModeEnabled: focusModeEnabled,
                                        focusRelatedItemIds: focusRelatedItemIds,
                                        textQuery: textQuery,
                                        showOverdueOnly: showOverdueOnly,
                                        showDueSoonOnly: showDueSoonOnly,
                                        showArchivedOnly: showArchivedOnly,
                                      );

                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 6),
                                        child: Text(
                                          '${visibleItems.length} item(s)',
                                          style: Theme.of(context).textTheme.labelMedium,
                                        ),
                                      );
                                    },
                                  ),
                                  Expanded(
                                    child: DragTarget<WorkItem>(
                                      onWillAcceptWithDetails: (details) {
                                        return details.data.columnId != column.columnId;
                                      },
                                      onAcceptWithDetails: (details) {
                                        final movedItem = details.data;
                                        if (movedItem.columnId == column.columnId) return;
                                        ref.read(boardControllerProvider).moveItem(
                                              itemId: movedItem.itemId,
                                              toColumnId: column.columnId,
                                            );
                                      },
                                      builder: (context, candidateData, rejectedData) {
                                        final isDropActive = candidateData.any(
                                          (item) => item != null && item.columnId != column.columnId,
                                        );

                                        return AnimatedContainer(
                                          duration: const Duration(milliseconds: 120),
                                          decoration: BoxDecoration(
                                            color: isDropActive
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .primaryContainer
                                                    .withValues(alpha: 0.35)
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: isDropActive
                                                  ? Theme.of(context).colorScheme.primary
                                                  : Colors.transparent,
                                            ),
                                          ),
                                          child: ListView(
                                            padding: const EdgeInsets.all(4),
                                            children: [
                                              for (final item in _sortedVisibleItems(
                                                items: snapshot.items,
                                                columnId: column.columnId,
                                                filter: visibilityFilter,
                                                focusModeEnabled: focusModeEnabled,
                                                focusRelatedItemIds: focusRelatedItemIds,
                                                textQuery: textQuery,
                                                showOverdueOnly: showOverdueOnly,
                                                showDueSoonOnly: showDueSoonOnly,
                                                showArchivedOnly: showArchivedOnly,
                                              ))
                                                _ItemTile(
                                                  item: item,
                                                  columns: columns,
                                                  allItems: snapshot.items,
                                                  focused: focusedItemId == item.itemId,
                                                  childCount:
                                                      snapshot.items.where((x) => x.parentId == item.itemId).length,
                                                  onSelect: () {
                                                    ref.read(focusedItemIdProvider.notifier).state = item.itemId;
                                                  },
                                                  onAddChildAction: () {
                                                    _showQuickAddChildActionDialog(
                                                      context,
                                                      ref,
                                                      parent: item,
                                                      columns: columns,
                                                    );
                                                  },
                                                  onEdit: () {
                                                    _showEditItemSheet(
                                                      context,
                                                      ref,
                                                      item: item,
                                                      allItems: snapshot.items,
                                                    );
                                                  },
                                                  onToggleArchive: () {
                                                    ref.read(boardControllerProvider).updateItem(
                                                          itemId: item.itemId,
                                                          archived: !item.archived,
                                                        );
                                                  },
                                                  onJumpToParent: item.parentId == null
                                                      ? null
                                                      : () {
                                                          ref.read(boardVisibilityFilterProvider.notifier).state =
                                                              BoardVisibilityFilter.allItems;
                                                          ref.read(focusedItemIdProvider.notifier).state =
                                                              item.parentId;
                                                          ref.read(focusModeEnabledProvider.notifier).state =
                                                              true;
                                                        },
                                                ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _ItemTile extends ConsumerWidget {
  static const _menuActionEdit = '__edit__';
  static const _menuActionAddChild = '__add_child__';
  static const _menuActionToggleArchive = '__toggle_archive__';

  const _ItemTile({
    required this.item,
    required this.columns,
    required this.allItems,
    required this.focused,
    required this.childCount,
    required this.onSelect,
    required this.onAddChildAction,
    required this.onEdit,
    required this.onToggleArchive,
    required this.onJumpToParent,
  });

  final WorkItem item;
  final List<BoardColumn> columns;
  final List<WorkItem> allItems;
  final bool focused;
  final int childCount;
  final VoidCallback onSelect;
  final VoidCallback onAddChildAction;
  final VoidCallback onEdit;
  final VoidCallback onToggleArchive;
  final VoidCallback? onJumpToParent;

  bool get _isOverdue {
    final dueAt = item.dueAt;
    if (dueAt == null) return false;
    if (item.completedAt != null) return false;
    return dueAt.isBefore(DateTime.now());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LongPressDraggable<WorkItem>(
      data: item,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedbackOffset: Offset.zero,
      onDragStarted: () {
        ref.read(activeDraggedItemProvider.notifier).state = item;
      },
      onDragEnd: (_) {
        ref.read(activeDraggedItemProvider.notifier).state = null;
      },
      onDraggableCanceled: (_, __) {
        ref.read(activeDraggedItemProvider.notifier).state = null;
      },
      onDragCompleted: () {
        ref.read(activeDraggedItemProvider.notifier).state = null;
      },
      feedback: Transform.translate(
        offset: const Offset(-50, -50),
        child: Material(
          color: Colors.transparent,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120, minWidth: 90),
              child: _buildDragFeedback(context),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: _buildCard(context, ref),
      ),
      child: _buildCard(context, ref),
    );
  }

  Widget _buildDragFeedback(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.drag_indicator, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).planDoneTokens;
    final doneColumnId = columns
        .where((c) => c.name.toLowerCase() == 'done')
        .map((c) => c.columnId)
        .cast<String?>()
        .firstWhere((_) => true, orElse: () => null);
    final fallbackColumnId = columns
        .where((c) => c.columnId != item.columnId)
        .map((c) => c.columnId)
        .cast<String?>()
        .firstWhere((_) => true, orElse: () => null);

    final parent = item.parentId == null
        ? null
        : allItems.where((x) => x.itemId == item.parentId).cast<WorkItem?>().firstWhere(
              (_) => true,
              orElse: () => null,
            );

    return Card(
      color: focused ? Theme.of(context).colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: onSelect,
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: focused
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                  ),
                  const SizedBox(height: 6),
                  if (parent != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: InkWell(
                        onTap: onJumpToParent,
                        child: Text(
                          'Parent: ${parent.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                decoration: TextDecoration.underline,
                              ),
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          item.type.name.toUpperCase(),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        if (childCount > 0)
                          Text(
                            'Children: $childCount',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        if (_isOverdue)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: tokens.warning.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'OVERDUE',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: tokens.warning, fontWeight: FontWeight.w700),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: item.columnId == doneColumnId ? 'Mark not done' : 'Mark done',
              onPressed: item.columnId == doneColumnId
                  ? (fallbackColumnId == null
                      ? null
                      : () => ref
                          .read(boardControllerProvider)
                          .moveItem(itemId: item.itemId, toColumnId: fallbackColumnId))
                  : (doneColumnId == null
                      ? null
                      : () => ref
                          .read(boardControllerProvider)
                          .moveItem(itemId: item.itemId, toColumnId: doneColumnId)),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              padding: EdgeInsets.zero,
              icon: Icon(
                item.columnId == doneColumnId ? Icons.remove_done_outlined : Icons.check_circle_outline,
                size: 18,
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (value) {
                if (value == _menuActionEdit) {
                  onEdit();
                  return;
                }
                if (value == _menuActionAddChild) {
                  onAddChildAction();
                  return;
                }
                if (value == _menuActionToggleArchive) {
                  onToggleArchive();
                  return;
                }
                ref.read(boardControllerProvider).moveItem(itemId: item.itemId, toColumnId: value);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: _menuActionEdit,
                  child: Text('Edit item'),
                ),
                const PopupMenuItem(
                  value: _menuActionAddChild,
                  child: Text('Add child action'),
                ),
                PopupMenuItem(
                  value: _menuActionToggleArchive,
                  child: Text(item.archived ? 'Unarchive' : 'Archive'),
                ),
                const PopupMenuDivider(),
                for (final column in columns)
                  PopupMenuItem(
                    value: column.columnId,
                    child: Text('Move to ${column.name}'),
                  ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}
