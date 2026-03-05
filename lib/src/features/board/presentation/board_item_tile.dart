import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/board_failures.dart';
import '../domain/models/board_validation_settings.dart';
import '../domain/models/column.dart';
import '../domain/models/work_item.dart';
import '../domain/policies/workflow_semantics_policy.dart';
import 'board_controller.dart';

class BoardItemTile extends ConsumerWidget {
  static const menuActionEdit = '__edit__';
  static const menuActionViewDetails = '__view_details__';
  static const menuActionAddChild = '__add_child__';
  static const menuActionToggleArchive = '__toggle_archive__';
  static const menuActionToggleSelected = '__toggle_selected__';
  static const menuActionReparent = '__reparent__';
  static const menuActionTriage = '__triage__';
  static const menuActionDelete = '__delete__';

  const BoardItemTile({
    super.key,
    required this.item,
    required this.columns,
    required this.allItems,
    required this.focused,
    required this.childCount,
    required this.onSelect,
    required this.onAddChildAction,
    required this.onEdit,
    required this.onViewDetails,
    required this.onToggleArchive,
    required this.onMoveToColumn,
    required this.onJumpToParent,
    required this.canModifyItems,
    required this.density,
    this.accentColor,
    this.showCompactParentSubtitle = false,
    this.parentPathMode = HierarchyParentPathMode.visible,
    this.selected = false,
    this.onToggleSelected,
    this.onReparent,
    this.onTriage,
    this.onDelete,
  });

  final WorkItem item;
  final List<BoardColumn> columns;
  final List<WorkItem> allItems;
  final bool focused;
  final bool selected;
  final int childCount;
  final VoidCallback onSelect;
  final VoidCallback onAddChildAction;
  final VoidCallback onEdit;
  final VoidCallback onViewDetails;
  final VoidCallback onToggleArchive;
  final Future<void> Function(String toColumnId) onMoveToColumn;
  final VoidCallback? onToggleSelected;
  final VoidCallback? onReparent;
  final VoidCallback? onTriage;
  final VoidCallback? onDelete;
  final VoidCallback? onJumpToParent;
  final bool canModifyItems;
  final BoardCardDensity density;
  final Color? accentColor;
  final bool showCompactParentSubtitle;
  final HierarchyParentPathMode parentPathMode;

  void _showActionFeedback(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _runGuardedAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on BoardPermissionDeniedException catch (error) {
      _showActionFeedback(context, error.message);
    } on BoardValidationException catch (error) {
      _showActionFeedback(context, error.message);
    } catch (error) {
      _showActionFeedback(context, 'Action failed: $error');
    }
  }

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
      maxSimultaneousDrags: canModifyItems ? null : 0,
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
    final compact = density == BoardCardDensity.compact;
    final doneColumnId = WorkflowSemanticsPolicy.doneColumn(columns)?.columnId;
    final fallbackColumnId = columns
        .where((c) => c.columnId != item.columnId)
        .map((c) => c.columnId)
        .cast<String?>()
        .firstWhere((_) => true, orElse: () => null);

    final parent = item.parentId == null
        ? null
        : allItems
            .where((x) => x.itemId == item.parentId)
            .cast<WorkItem?>()
            .firstWhere(
              (_) => true,
              orElse: () => null,
            );
    final toggleDoneAction = !canModifyItems
        ? null
        : item.columnId == doneColumnId
            ? (fallbackColumnId == null
                ? null
                : () => _runGuardedAction(
                      context,
                      () => onMoveToColumn(fallbackColumnId),
                    ))
            : (doneColumnId == null
                ? null
                : () => _runGuardedAction(
                      context,
                      () => onMoveToColumn(doneColumnId),
                    ));

    Widget buildOverflowMenu({bool compactMenu = false}) {
      final button = PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        iconSize: compactMenu ? 16 : 18,
        icon: Icon(Icons.more_vert, size: compactMenu ? 16 : 18),
        onSelected: (value) {
          if (!canModifyItems) {
            _showActionFeedback(
              context,
              'Current role cannot modify items in this board.',
            );
            return;
          }
          if (value == menuActionEdit) {
            onEdit();
            return;
          }
          if (value == menuActionViewDetails) {
            onViewDetails();
            return;
          }
          if (value == menuActionAddChild) {
            onAddChildAction();
            return;
          }
          if (value == menuActionToggleArchive) {
            onToggleArchive();
            return;
          }
          if (value == menuActionToggleSelected) {
            onToggleSelected?.call();
            return;
          }
          if (value == menuActionReparent) {
            onReparent?.call();
            return;
          }
          if (value == menuActionTriage) {
            onTriage?.call();
            return;
          }
          if (value == menuActionDelete) {
            onDelete?.call();
            return;
          }
          _runGuardedAction(
            context,
            () => onMoveToColumn(value),
          );
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: menuActionEdit,
            child: Text('Edit item'),
          ),
          const PopupMenuItem(
            value: menuActionViewDetails,
            child: Text('View details'),
          ),
          const PopupMenuItem(
            value: menuActionAddChild,
            child: Text('Add child action'),
          ),
          PopupMenuItem(
            value: menuActionToggleArchive,
            child: Text(item.archived ? 'Unarchive' : 'Archive'),
          ),
          if (onToggleSelected != null)
            PopupMenuItem(
              value: menuActionToggleSelected,
              child: Text(selected ? 'Deselect' : 'Select for bulk'),
            ),
          if (onReparent != null)
            const PopupMenuItem(
              value: menuActionReparent,
              child: Text('Re-parent'),
            ),
          if (onTriage != null)
            const PopupMenuItem(
              value: menuActionTriage,
              child: Text('Triage inbox item'),
            ),
          if (onDelete != null)
            const PopupMenuItem(
              value: menuActionDelete,
              child: Text('Delete item'),
            ),
          const PopupMenuDivider(),
          for (final column in columns)
            PopupMenuItem(
              value: column.columnId,
              child: Text('Move to ${column.name}'),
            ),
        ],
      );
      if (!compactMenu) return button;
      return SizedBox(width: 28, height: 28, child: button);
    }

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 0, vertical: compact ? 2 : 4),
      color: selected
          ? Theme.of(context).colorScheme.secondaryContainer
          : (focused ? Theme.of(context).colorScheme.primaryContainer : null),
      child: InkWell(
        onTap: onSelect,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 5 : 8,
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (accentColor != null)
                  Container(
                    width: compact ? 3 : 4,
                    margin: EdgeInsets.only(right: compact ? 6 : 8),
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                if (onToggleSelected != null && !compact)
                  IconButton(
                    tooltip: selected ? 'Deselect item' : 'Select item',
                    onPressed: onToggleSelected,
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints.tightFor(width: 28, height: 28),
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 18,
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (compact) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Tooltip(
                                message: item.title,
                                child: Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: focused
                                            ? Theme.of(context)
                                                .colorScheme
                                                .onPrimaryContainer
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                      ),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: item.columnId == doneColumnId
                                  ? 'Mark not done'
                                  : 'Mark done',
                              onPressed: toggleDoneAction,
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(
                                  width: 30, height: 30),
                              padding: EdgeInsets.zero,
                              icon: Icon(
                                item.columnId == doneColumnId
                                    ? Icons.remove_done_outlined
                                    : Icons.check_circle_outline,
                                size: 16,
                              ),
                            ),
                            buildOverflowMenu(compactMenu: true),
                          ],
                        ),
                        if (parent != null &&
                            parentPathMode !=
                                HierarchyParentPathMode.hidden) ...[
                          const SizedBox(height: 1),
                          InkWell(
                            onTap: onJumpToParent,
                            child: Text(
                              showCompactParentSubtitle
                                  ? (parentPathMode ==
                                          HierarchyParentPathMode.visible
                                      ? 'Parent: ${parent.title}'
                                      : parent.title)
                                  : 'Parent',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withValues(
                                          alpha: parentPathMode ==
                                                  HierarchyParentPathMode.subtle
                                              ? 0.8
                                              : 1,
                                        ),
                                  ),
                            ),
                          ),
                        ],
                      ] else ...[
                        Tooltip(
                          message: item.title,
                          child: Text(
                            item.title,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: focused
                                      ? Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (parent != null &&
                            parentPathMode != HierarchyParentPathMode.hidden)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: InkWell(
                              onTap: onJumpToParent,
                              child: Text(
                                parentPathMode ==
                                        HierarchyParentPathMode.visible
                                    ? 'Parent: ${parent.title}'
                                    : parent.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      decoration: parentPathMode ==
                                              HierarchyParentPathMode.visible
                                          ? TextDecoration.underline
                                          : TextDecoration.none,
                                    ),
                              ),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                item.type.name.toUpperCase(),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              if (childCount > 0)
                                Text(
                                  'Children: $childCount',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              if (_isOverdue)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .errorContainer,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    'OVERDUE',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onErrorContainer,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: item.columnId == doneColumnId
                                    ? 'Mark not done'
                                    : 'Mark done',
                                onPressed: toggleDoneAction,
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints.tightFor(
                                    width: 32, height: 32),
                                padding: EdgeInsets.zero,
                                icon: Icon(
                                  item.columnId == doneColumnId
                                      ? Icons.remove_done_outlined
                                      : Icons.check_circle_outline,
                                  size: 18,
                                ),
                              ),
                              buildOverflowMenu(),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
