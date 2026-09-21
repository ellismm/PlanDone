// ignore_for_file: unused_element, use_build_context_synchronously

import 'dart:async';
import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_navigation_shell.dart';
import '../../../app_routes.dart';
import '../../../core/help/app_help.dart';
import '../../../core/help/app_help_widgets.dart';
import '../../../core/runtime/runtime_flags.dart';
import '../../../core/sync/sync_retry_scheduler.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/models/board_failures.dart';
import '../domain/models/board.dart';
import '../domain/models/board_calendar_preferences.dart';
import '../domain/models/board_filter_preset.dart';
import '../domain/models/board_member.dart';
import '../domain/models/board_reminder_alert.dart';
import '../domain/models/board_snapshot.dart';
import '../domain/models/board_validation_settings.dart';
import '../domain/models/board_workflow_settings.dart';
import '../domain/models/column.dart';
import '../domain/models/autofill_settings.dart';
import '../domain/models/notification_preferences.dart';
import '../domain/models/work_item.dart';
import '../domain/models/work_item_activity_event.dart';
import '../domain/models/work_item_recurrence.dart';
import '../domain/models/work_item_type.dart';
import '../domain/policies/autofill_suggestion_policy.dart';
import '../domain/policies/board_calendar_policy.dart';
import '../domain/policies/board_permissions.dart';
import '../domain/policies/board_validation_policy.dart';
import '../domain/policies/create_item_defaults_policy.dart';
import '../domain/policies/hierarchy_context_policy.dart';
import '../domain/policies/notification_reminder_policy.dart';
import '../domain/policies/workflow_semantics_policy.dart';
import 'board_calendar_view.dart';
import 'board_controller.dart';
import 'board_item_details_sheet.dart';
import 'board_item_tile.dart';
import 'board_view_ui.dart';
import 'hierarchy_visuals.dart';
import 'workspace_attention.dart';

enum _ReminderSection {
  overdue,
  dueSoon,
  startingSoon,
}

String _itemAccentKey({
  required String boardId,
  required String itemId,
}) =>
    '$boardId::$itemId';

Map<String, int> _resolveItemAccentColorValues({
  required Map<String, List<WorkItem>> itemsByBoardId,
  required Map<String, BoardValidationSettings> settingsByBoardId,
}) {
  final accentColorsByItemKey = <String, int>{};

  for (final entry in itemsByBoardId.entries) {
    final boardId = entry.key;
    final boardItems = entry.value;
    final settings =
        settingsByBoardId[boardId] ?? const BoardValidationSettings();
    if (!settings.hierarchyColorGroupingByGoal || boardItems.isEmpty) {
      continue;
    }

    final boardItemsById = {
      for (final item in boardItems) item.itemId: item,
    };
    final goalColors = resolveGoalColors(
      items: boardItems,
      overrides: settings.hierarchyGoalColorOverrides,
    );

    for (final item in boardItems) {
      final topGoalId = topLevelGoalIdForItem(item, boardItemsById);
      final accentColorValue = topGoalId == null ? null : goalColors[topGoalId];
      if (accentColorValue == null) continue;
      accentColorsByItemKey[
              _itemAccentKey(boardId: item.boardId, itemId: item.itemId)] =
          accentColorValue;
    }
  }

  return accentColorsByItemKey;
}

class _NearFingerColumnTargets {
  const _NearFingerColumnTargets({
    required this.left,
    required this.right,
  });

  final List<BoardColumn> left;
  final List<BoardColumn> right;

  bool get isEmpty => left.isEmpty && right.isEmpty;
}

class _DockedColumnOverlayMetrics {
  const _DockedColumnOverlayMetrics({
    required this.targetHeight,
    required this.targetSpacing,
    required this.verticalPadding,
    required this.iconSize,
    required this.labelStyle,
  });

  final double targetHeight;
  final double targetSpacing;
  final double verticalPadding;
  final double iconSize;
  final TextStyle labelStyle;
}

class BoardPage extends ConsumerWidget {
  const BoardPage({super.key});

  void _showActionFeedback(
    BuildContext context,
    String message, {
    WorkspaceFeedbackSeverity severity = WorkspaceFeedbackSeverity.error,
  }) {
    if (!context.mounted) return;
    ProviderScope.containerOf(
      context,
      listen: false,
    ).read(boardControllerProvider).enqueueWorkspaceFeedback(
          message,
          severity: severity,
        );
  }

  Future<bool> _confirmDestructiveAction(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  String _formatRetryTime(DateTime retryAt) {
    final diff = retryAt.difference(DateTime.now());
    if (diff.inSeconds <= 0) return 'now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    return '${diff.inHours}h ${diff.inMinutes % 60}m';
  }

  Future<bool> _runGuardedAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      return true;
    } on BoardPermissionDeniedException catch (error) {
      _showActionFeedback(context, error.message);
    } on BoardValidationException catch (error) {
      _showActionFeedback(context, error.message);
    } catch (error) {
      _showActionFeedback(context, 'Action failed: $error');
    }
    return false;
  }

  Future<T?> _runGuardedActionWithResult<T>(
    BuildContext context,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on BoardPermissionDeniedException catch (error) {
      _showActionFeedback(context, error.message);
    } on BoardValidationException catch (error) {
      _showActionFeedback(context, error.message);
    } catch (error) {
      _showActionFeedback(context, 'Action failed: $error');
    }
    return null;
  }

  AppHelpTargetSpec _workspaceControlsHelpSpec() {
    return const AppHelpTargetSpec(
      id: AppHelpTargetIds.workspaceControls,
      title: 'Workspace controls',
      description:
          'This strip is where you steer what the workspace is showing right now.',
      whenToUse:
          'Use it when you want to switch board scope, change the view, filter what is visible, open reminders, or search for something fast.',
      whatHappens:
          'Each control updates the current workspace surface right away, so you can stay in context while planning.',
      icon: Icons.space_dashboard_outlined,
    );
  }

  AppHelpTargetSpec _workspaceCaptureHelpSpec() {
    return const AppHelpTargetSpec(
      id: AppHelpTargetIds.workspaceCapture,
      title: 'Capture',
      description:
          'Capture is the fast way to throw a thought into the system before it disappears.',
      whenToUse:
          'Use it when something pops into your head and you want to save it without deciding all the details yet.',
      whatHappens:
          'It opens a lighter capture flow so you can save the idea quickly and organize it properly later.',
      icon: Icons.flash_on_outlined,
      tourId: AppHelpTourId.workspace,
    );
  }

  AppHelpTargetSpec _workspaceBoardScopeHelpSpec() {
    return const AppHelpTargetSpec(
      id: AppHelpTargetIds.workspaceBoardScope,
      title: 'Board scope',
      description:
          'This control decides which boards the workspace is currently showing.',
      whenToUse:
          'Use it when you want to stay on one board, compare a few boards together, or look across everything at once.',
      whatHappens:
          'Changing board scope updates the visible items, reminders, and calendar data without leaving the workspace.',
      icon: Icons.view_list_outlined,
      tourId: AppHelpTourId.workspace,
    );
  }

  AppHelpTargetSpec _workspaceViewPickerHelpSpec() {
    return const AppHelpTargetSpec(
      id: AppHelpTargetIds.workspaceViewPicker,
      title: 'View picker',
      description:
          'The view picker changes how the same work is laid out on screen.',
      whenToUse:
          'Use it when you want to switch between structure, board flow, and calendar planning without losing your place.',
      whatHappens:
          'The current workspace data stays the same, but the surface changes to the selected planning view.',
      icon: Icons.dashboard_outlined,
      tourId: AppHelpTourId.workspace,
    );
  }

  AppHelpTargetSpec _workspaceFiltersHelpSpec() {
    return const AppHelpTargetSpec(
      id: AppHelpTargetIds.workspaceFilters,
      title: 'Filters',
      description:
          'Filters narrow the workspace down to the work you want to think about right now.',
      whenToUse:
          'Use them when the board feels noisy and you want to focus on certain item types, states, tags, or date-based slices.',
      whatHappens:
          'The current view updates in place, and active filters stay visible through the badge count.',
      icon: Icons.filter_list,
      tourId: AppHelpTourId.workspace,
    );
  }

  AppHelpTargetSpec _workspaceRemindersHelpSpec() {
    return const AppHelpTargetSpec(
      id: AppHelpTargetIds.workspaceReminders,
      title: 'Reminders',
      description:
          'Reminders show what needs attention soon without forcing you out of the workspace.',
      whenToUse:
          'Use this when you want to review overdue or upcoming items and act on them quickly.',
      whatHappens:
          'It opens the reminder center so you can snooze, complete, or inspect the items asking for attention.',
      icon: Icons.notifications_none_outlined,
      tourId: AppHelpTourId.workspace,
    );
  }

  AppHelpTargetSpec _workspaceSearchHelpSpec() {
    return const AppHelpTargetSpec(
      id: AppHelpTargetIds.workspaceSearch,
      title: 'Search',
      description:
          'Search lets you jump straight to the item you need without changing boards or views manually.',
      whenToUse:
          'Use it when you know the title or part of the wording and want to narrow the workspace quickly.',
      whatHappens:
          'Typing filters the current workspace in place, and collapsing search keeps the rest of the controls compact.',
      icon: Icons.search,
      tourId: AppHelpTourId.workspace,
    );
  }

  AppHelpTargetSpec _workspaceHierarchyControlsHelpSpec() {
    return const AppHelpTargetSpec(
      id: AppHelpTargetIds.workspaceHierarchyControls,
      title: 'Hierarchy controls',
      description:
          'These controls help you expand, collapse, and reset the branch you are looking at.',
      whenToUse:
          'Use them when the tree is too broad, when you want to focus on one branch, or when you want to clear the current hierarchy selection.',
      whatHappens:
          'You can open more of the tree, fold it back down, or clear the selected item without leaving hierarchy view.',
      icon: Icons.unfold_more,
      tourId: AppHelpTourId.hierarchy,
    );
  }

  AppHelpTargetSpec _workspaceTopFocusHelpSpec() {
    return const AppHelpTargetSpec(
      id: AppHelpTargetIds.workspaceTopFocus,
      title: 'Focus shortcut',
      description:
          'This opens Focus view directly from the top banner without cycling through the regular workspace layouts.',
      whenToUse:
          'Use it when you want to zero in on one item and its surrounding context right away.',
      whatHappens:
          'The workspace switches into Focus view so you can work around the selected item with less visual noise.',
      icon: Icons.filter_center_focus_outlined,
    );
  }

  AppHelpTargetSpec _workspaceTopToolsHelpSpec() {
    return const AppHelpTargetSpec(
      id: AppHelpTargetIds.workspaceTopTools,
      title: 'Workspace tools',
      description:
          'This opens the quick tools surface for reminders, notifications, and other workspace-level actions.',
      whenToUse:
          'Use it when you want a fast way to review what needs attention without leaving the workspace.',
      whatHappens:
          'The tools surface opens and can show badges when reminders, inbox items, or notices need a look.',
      icon: Icons.tune,
      tourId: AppHelpTourId.workspace,
    );
  }

  AppHelpTargetSpec _workspaceSurfaceHelpSpec({
    required BoardPlanningView planningView,
    required BoardWorkspaceSurface workspaceSurface,
  }) {
    if (workspaceSurface == BoardWorkspaceSurface.inbox) {
      return const AppHelpTargetSpec(
        id: AppHelpTargetIds.workspaceInboxSurface,
        title: 'Inbox triage',
        description:
            'Inbox is the place for unprocessed captures that still need a real decision.',
        whenToUse:
            'Use it when you want to turn quick captures into proper work items, move them to a board, or clear incoming clutter.',
        whatHappens:
            'You can review items one by one, decide what they really are, and place them into a board and column.',
        icon: Icons.inbox_outlined,
        tourId: AppHelpTourId.workspace,
      );
    }

    switch (planningView) {
      case BoardPlanningView.hierarchy:
        return const AppHelpTargetSpec(
          id: AppHelpTargetIds.workspaceHierarchySurface,
          title: 'Hierarchy view',
          description:
              'Hierarchy shows how goals, projects, tasks, and actions connect to each other.',
          whenToUse:
              'Use it when you want to understand structure, check parent-child relationships, or work down from larger goals.',
          whatHappens:
              'Selecting an item helps you follow its branch, expand or collapse context, and understand how work rolls up.',
          icon: Icons.account_tree_outlined,
          tourId: AppHelpTourId.hierarchy,
        );
      case BoardPlanningView.kanban:
      case BoardPlanningView.backlog:
      case BoardPlanningView.focus:
      case BoardPlanningView.calendar:
        return const AppHelpTargetSpec(
          id: AppHelpTargetIds.workspaceKanbanSurface,
          title: 'Board view',
          description:
              'This is the active workspace surface where you move work, inspect items, and decide what happens next.',
          whenToUse:
              'Use it when you want to work directly with the current board state instead of just adjusting filters or settings.',
          whatHappens:
              'You can select items, open details, drag between columns when supported, and use the current view to plan from a different angle.',
          icon: Icons.view_kanban_outlined,
          tourId: AppHelpTourId.workspace,
        );
    }
  }

  List<DropdownMenuItem<int?>> _goalColorMenuItems({
    required int autoColor,
  }) {
    return [
      DropdownMenuItem<int?>(
        value: null,
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Color(autoColor),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            const Text('Auto (random unused)'),
          ],
        ),
      ),
      for (var i = 0; i < hierarchyGoalColorPalette.length; i++)
        DropdownMenuItem<int?>(
          value: hierarchyGoalColorPalette[i],
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Color(hierarchyGoalColorPalette[i]),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Text('Palette ${i + 1}'),
            ],
          ),
        ),
    ];
  }

  Future<void> _moveItemWithUndo(
    BuildContext context,
    WidgetRef ref, {
    required WorkItem item,
    required String toColumnId,
  }) async {
    if (item.columnId == toColumnId) return;
    final moved = await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).moveItem(
            boardId: item.boardId,
            itemId: item.itemId,
            toColumnId: toColumnId,
          ),
    );
    if (!moved) return;
    ref.read(boardControllerProvider).stageMoveUndo(
          item: item,
          fromBoardId: item.boardId,
          fromColumnId: item.columnId,
          toBoardId: item.boardId,
          toColumnId: toColumnId,
        );
  }

  Future<void> _rescheduleItemDueDateWithUndo(
    BuildContext context,
    WidgetRef ref, {
    required WorkItem item,
    required DateTime dueAt,
  }) async {
    final normalizedDueAt = DateTime(dueAt.year, dueAt.month, dueAt.day);
    final previousDueAt = item.dueAt == null
        ? null
        : DateTime(
            item.dueAt!.year,
            item.dueAt!.month,
            item.dueAt!.day,
          );
    if (previousDueAt != null &&
        previousDueAt.year == normalizedDueAt.year &&
        previousDueAt.month == normalizedDueAt.month &&
        previousDueAt.day == normalizedDueAt.day) {
      return;
    }

    final updated = await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).updateItem(
            boardId: item.boardId,
            itemId: item.itemId,
            dueAt: normalizedDueAt,
          ),
    );
    if (!updated) return;
    ref.read(boardControllerProvider).stageDueDateUndo(
          item: item,
          fromDueAt: previousDueAt,
          toDueAt: normalizedDueAt,
        );
  }

  _NearFingerColumnTargets? _nearFingerTargetsForItem(
    WorkItem item, {
    required List<BoardColumn> columns,
  }) {
    final orderedColumns = [...columns]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    if (orderedColumns.length < 2) return null;
    final currentIndex = orderedColumns.indexWhere(
      (column) => column.columnId == item.columnId,
    );
    if (currentIndex < 0) return null;
    final left = orderedColumns.take(currentIndex).toList().reversed.toList();
    final right = orderedColumns.skip(currentIndex + 1).toList();
    final targets = _NearFingerColumnTargets(left: left, right: right);
    return targets.isEmpty ? null : targets;
  }

  double _staticSideOverlayTop({
    required int itemCount,
    required double rowHeight,
    required double rowSpacing,
    required double maxHeight,
  }) {
    if (itemCount <= 0) return 12;
    final totalHeight = itemCount * rowHeight + (itemCount - 1) * rowSpacing;
    final desiredTop = (maxHeight - totalHeight) / 2;
    return desiredTop
        .clamp(12.0, max(12.0, maxHeight - totalHeight - 12.0))
        .toDouble();
  }

  _DockedColumnOverlayMetrics _dockedColumnOverlayMetrics(
    BuildContext context, {
    required int maxTargetCount,
    required double viewportHeight,
  }) {
    const baseHeight = 58.0;
    const baseSpacing = 10.0;
    const minHeight = 40.0;
    const minSpacing = 4.0;
    final availableHeight = max(160.0, viewportHeight - 24.0);

    if (maxTargetCount <= 1) {
      return _DockedColumnOverlayMetrics(
        targetHeight: baseHeight,
        targetSpacing: baseSpacing,
        verticalPadding: 14,
        iconSize: 18,
        labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ) ??
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      );
    }

    final baseTotalHeight =
        maxTargetCount * baseHeight + (maxTargetCount - 1) * baseSpacing;
    final adjustedHeight = baseTotalHeight <= availableHeight
        ? baseHeight
        : ((availableHeight - (maxTargetCount - 1) * minSpacing) /
                maxTargetCount)
            .clamp(minHeight, baseHeight)
            .toDouble();
    final adjustedSpacing = maxTargetCount <= 1
        ? baseSpacing
        : ((availableHeight - maxTargetCount * adjustedHeight) /
                (maxTargetCount - 1))
            .clamp(minSpacing, baseSpacing)
            .toDouble();

    final compactness =
        ((baseHeight - adjustedHeight) / (baseHeight - minHeight))
            .clamp(0.0, 1.0);
    final verticalPadding = lerpDouble(14, 8, compactness) ?? 14;
    final iconSize = lerpDouble(18, 16, compactness) ?? 18;
    final fontSize = lerpDouble(14, 12, compactness) ?? 14;

    return _DockedColumnOverlayMetrics(
      targetHeight: adjustedHeight,
      targetSpacing: adjustedSpacing,
      verticalPadding: verticalPadding,
      iconSize: iconSize,
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: fontSize,
              ) ??
          TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700),
    );
  }

  Widget _buildNearFingerColumnTarget({
    required BuildContext context,
    required WidgetRef ref,
    required WorkItem draggedItem,
    required BoardColumn column,
    required bool canModifyItems,
    required bool dockLeft,
    required _DockedColumnOverlayMetrics metrics,
  }) {
    return DragTarget<WorkItem>(
      key: ValueKey('side-column-target-${column.columnId}'),
      onWillAcceptWithDetails: (details) {
        return canModifyItems &&
            details.data.boardId == draggedItem.boardId &&
            details.data.columnId != column.columnId;
      },
      onAcceptWithDetails: (details) {
        if (!canModifyItems) {
          _showActionFeedback(
            context,
            'Current role cannot modify items in this board.',
          );
          return;
        }
        _moveItemWithUndo(
          context,
          ref,
          item: details.data,
          toColumnId: column.columnId,
        );
      },
      builder: (context, candidateData, rejectedData) {
        final isDropActive = candidateData.any(
          (item) =>
              item != null &&
              item.boardId == draggedItem.boardId &&
              item.columnId != column.columnId,
        );
        final theme = Theme.of(context);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          constraints: BoxConstraints(minHeight: metrics.targetHeight),
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: metrics.verticalPadding,
          ),
          decoration: BoxDecoration(
            color: isDropActive
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHigh,
            borderRadius: dockLeft
                ? const BorderRadius.horizontal(right: Radius.circular(18))
                : const BorderRadius.horizontal(left: Radius.circular(18)),
            border: Border.all(
              color: isDropActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isDropActive ? Icons.move_down : Icons.swap_horiz,
                size: metrics.iconSize,
                color: isDropActive
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  column.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: metrics.labelStyle.copyWith(
                    color: isDropActive
                        ? theme.colorScheme.onPrimaryContainer
                        : null,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNearFingerColumnMoveOverlay(
    BuildContext context,
    WidgetRef ref, {
    required WorkItem draggedItem,
    required List<BoardColumn> boardColumns,
    required bool canModifyItems,
    required double viewportHeight,
  }) {
    final targets = _nearFingerTargetsForItem(
      draggedItem,
      columns: boardColumns,
    );
    if (targets == null || targets.isEmpty) {
      return const SizedBox.shrink();
    }

    const targetWidth = 184.0;
    final metrics = _dockedColumnOverlayMetrics(
      context,
      maxTargetCount: max(targets.left.length, targets.right.length),
      viewportHeight: viewportHeight,
    );
    final leftTop = _staticSideOverlayTop(
      itemCount: targets.left.length,
      rowHeight: metrics.targetHeight,
      rowSpacing: metrics.targetSpacing,
      maxHeight: viewportHeight,
    );
    final rightTop = _staticSideOverlayTop(
      itemCount: targets.right.length,
      rowHeight: metrics.targetHeight,
      rowSpacing: metrics.targetSpacing,
      maxHeight: viewportHeight,
    );

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Stack(
          key: const ValueKey('near-finger-column-overlay'),
          children: [
            if (targets.left.isNotEmpty)
              Positioned(
                left: 0,
                top: leftTop,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: targetWidth,
                    maxWidth: targetWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < targets.left.length; index++)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: index == targets.left.length - 1
                                ? 0
                                : metrics.targetSpacing,
                          ),
                          child: _buildNearFingerColumnTarget(
                            context: context,
                            ref: ref,
                            draggedItem: draggedItem,
                            column: targets.left[index],
                            canModifyItems: canModifyItems,
                            dockLeft: true,
                            metrics: metrics,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (targets.right.isNotEmpty)
              Positioned(
                right: 0,
                top: rightTop,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: targetWidth,
                    maxWidth: targetWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < targets.right.length; index++)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: index == targets.right.length - 1
                                ? 0
                                : metrics.targetSpacing,
                          ),
                          child: _buildNearFingerColumnTarget(
                            context: context,
                            ref: ref,
                            draggedItem: draggedItem,
                            column: targets.right[index],
                            canModifyItems: canModifyItems,
                            dockLeft: false,
                            metrics: metrics,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleArchiveWithUndo(
    BuildContext context,
    WidgetRef ref, {
    required WorkItem item,
  }) async {
    final nextArchived = !item.archived;
    final updated = await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).updateItem(
            boardId: item.boardId,
            itemId: item.itemId,
            archived: nextArchived,
          ),
    );
    if (!updated) return;
    ref.read(boardControllerProvider).stageArchiveUndo(
          item: item,
          fromArchived: item.archived,
          toArchived: nextArchived,
        );
  }

  Future<void> _deleteItemWithUndo(
    BuildContext context,
    WidgetRef ref, {
    required WorkItem item,
    required List<WorkItem> allItems,
  }) async {
    final hasChildren = allItems.any((entry) => entry.parentId == item.itemId);
    if (hasChildren) {
      _showActionFeedback(
        context,
        'Cannot delete an item with children. Re-parent or delete children first.',
      );
      return;
    }
    final confirmed = await _confirmDestructiveAction(
      context,
      title: 'Delete item?',
      message: 'Delete "${item.title}"?',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;

    final deleted = await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).deleteItem(
            boardId: item.boardId,
            itemId: item.itemId,
          ),
    );
    if (!deleted) return;
    ref.read(boardControllerProvider).stageDeleteUndo(item: item);
  }

  Future<String?> _pickTargetColumnForBoard(
    BuildContext context,
    WidgetRef ref, {
    required String boardId,
  }) async {
    final targetSnapshot =
        await ref.read(localBoardStoreProvider).getBoard(boardId);
    final ordered = [...targetSnapshot.columns]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
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
    final targetColumnId =
        await _pickTargetColumnForBoard(context, ref, boardId: targetBoardId);
    if (targetColumnId == null) return;

    final sourceBoardId = item.boardId;
    final sourceColumnId = item.columnId;

    final moved = await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).moveItemToBoard(
            itemId: item.itemId,
            toBoardId: targetBoardId,
            toColumnId: targetColumnId,
          ),
    );
    if (!moved) return;
    ref.read(boardControllerProvider).stageMoveUndo(
          item: item,
          fromBoardId: sourceBoardId,
          fromColumnId: sourceColumnId,
          toBoardId: targetBoardId,
          toColumnId: targetColumnId,
        );
  }

  Future<void> _reorderItemFromDrop(
    BuildContext context,
    WidgetRef ref, {
    required WorkItem item,
    required String boardId,
    String? toColumnId,
    String? parentId,
    bool clearParent = false,
    String? beforeItemId,
    String? afterItemId,
  }) async {
    await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).reorderItem(
            boardId: boardId,
            itemId: item.itemId,
            toColumnId: toColumnId,
            parentId: parentId,
            clearParent: clearParent,
            beforeItemId: beforeItemId,
            afterItemId: afterItemId,
          ),
    );
  }

  Widget _buildReorderGapTarget(
    BuildContext context,
    WidgetRef ref, {
    required bool enabled,
    required String boardId,
    required String? beforeItemId,
    required String? afterItemId,
    String? toColumnId,
    String? parentId,
    bool clearParent = false,
    double thickness = 10,
    EdgeInsetsGeometry margin = EdgeInsets.zero,
  }) {
    return DragTarget<WorkItem>(
      onWillAcceptWithDetails: (details) {
        if (!enabled) return false;
        if (details.data.boardId != boardId) return false;
        if (details.data.itemId == beforeItemId ||
            details.data.itemId == afterItemId) {
          return false;
        }
        return true;
      },
      onAcceptWithDetails: (details) {
        unawaited(
          _reorderItemFromDrop(
            context,
            ref,
            item: details.data,
            boardId: boardId,
            toColumnId: toColumnId,
            parentId: parentId,
            clearParent: clearParent,
            beforeItemId: beforeItemId,
            afterItemId: afterItemId,
          ),
        );
      },
      builder: (context, candidateData, rejectedData) {
        final isDropActive = candidateData.any(
          (item) => item != null && item.boardId == boardId,
        );
        return Container(
          height: isDropActive ? thickness + 6 : thickness,
          margin: margin,
          decoration: BoxDecoration(
            color: isDropActive
                ? Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isDropActive
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
            ),
          ),
        );
      },
    );
  }

  String _typeFilterLabel(WorkItemType type) {
    return switch (type) {
      WorkItemType.goal => 'Goals',
      WorkItemType.project => 'Projects',
      WorkItemType.task => 'Tasks',
      WorkItemType.action => 'Actions',
    };
  }

  String _stateFilterLabel(BoardItemStateFilter filter) {
    return switch (filter) {
      BoardItemStateFilter.any => 'Any state',
      BoardItemStateFilter.active => 'Active',
      BoardItemStateFilter.done => 'Done',
      BoardItemStateFilter.blocked => 'Blocked',
      BoardItemStateFilter.cancelled => 'Cancelled',
      BoardItemStateFilter.urgent => 'Urgent',
      BoardItemStateFilter.overdue => 'Overdue',
      BoardItemStateFilter.dueSoon => 'Due ≤ 7d',
    };
  }

  String _reminderKindLabel(BoardReminderKind kind) {
    return switch (kind) {
      BoardReminderKind.start => 'Start',
      BoardReminderKind.due => 'Due',
    };
  }

  _ReminderSection _reminderSection(BoardReminderAlert reminder) {
    if (reminder.isOverdue) return _ReminderSection.overdue;
    return switch (reminder.kind) {
      BoardReminderKind.due => _ReminderSection.dueSoon,
      BoardReminderKind.start => _ReminderSection.startingSoon,
    };
  }

  String _reminderSectionLabel(_ReminderSection section) {
    return switch (section) {
      _ReminderSection.overdue => 'Overdue',
      _ReminderSection.dueSoon => 'Due soon',
      _ReminderSection.startingSoon => 'Starting soon',
    };
  }

  IconData _reminderSectionIcon(_ReminderSection section) {
    return switch (section) {
      _ReminderSection.overdue => Icons.warning_amber_rounded,
      _ReminderSection.dueSoon => Icons.notifications_active_outlined,
      _ReminderSection.startingSoon => Icons.play_circle_outline,
    };
  }

  bool _canQuickCompleteReminder(BoardReminderAlert reminder) {
    return NotificationReminderPolicy.supportsQuickComplete(reminder.item);
  }

  Map<_ReminderSection, List<BoardReminderAlert>> _groupReminders(
    List<BoardReminderAlert> reminders,
  ) {
    final grouped = <_ReminderSection, List<BoardReminderAlert>>{
      for (final section in _ReminderSection.values)
        section: <BoardReminderAlert>[],
    };
    for (final reminder in reminders) {
      grouped[_reminderSection(reminder)]!.add(reminder);
    }
    return grouped;
  }

  String _reminderAttentionLine(
    BoardReminderAlert reminder, {
    required bool showBoardContext,
  }) {
    if (showBoardContext && reminder.boardName.isNotEmpty) {
      return '${reminder.boardName} • ${reminder.message}';
    }
    return reminder.message;
  }

  Future<void> _openReminderDetails(
    BuildContext context,
    WidgetRef ref, {
    required BoardReminderAlert reminder,
  }) async {
    final snapshot =
        await ref.read(localBoardStoreProvider).getBoard(reminder.item.boardId);
    if (!context.mounted) return;
    return _showItemDetailsSheet(
      context,
      ref,
      item: reminder.item,
      allItems: snapshot.items,
      columns: snapshot.columns,
      settings: snapshot.board.validationSettings,
    );
  }

  Future<void> _handleReminderDone(
    BuildContext context,
    WidgetRef ref, {
    required BoardReminderAlert reminder,
  }) {
    return _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).completeReminderAsDone(
            boardId: reminder.item.boardId,
            itemId: reminder.item.itemId,
          ),
    );
  }

  Future<void> _runWorkspaceNoticeAction(
    BuildContext context,
    WidgetRef ref, {
    required WorkspaceAttentionNotice notice,
    required WorkspaceNoticeAction action,
  }) async {
    switch (action.kind) {
      case WorkspaceNoticeActionKind.reminderDone:
        final reminder = notice.reminder;
        if (reminder == null) return;
        await _handleReminderDone(context, ref, reminder: reminder);
        break;
      case WorkspaceNoticeActionKind.reminderOpen:
        final reminder = notice.reminder;
        if (reminder == null) return;
        await _openReminderDetails(context, ref, reminder: reminder);
        break;
      case WorkspaceNoticeActionKind.reminderSnooze:
        final reminder = notice.reminder;
        if (reminder == null) return;
        await _runGuardedAction(
          context,
          () => ref.read(boardControllerProvider).snoozeReminder(
                reminderId: reminder.reminderId,
              ),
        );
        break;
      case WorkspaceNoticeActionKind.retrySync:
        await _triggerSyncNow(context, ref);
        break;
      case WorkspaceNoticeActionKind.reviewSync:
        await _showOutboxSheet(context, ref);
        break;
    }
  }

  String _recurrenceMissedWindowLabel(
    WorkItemRecurrenceMissedWindowPolicy policy,
  ) {
    return switch (policy) {
      WorkItemRecurrenceMissedWindowPolicy.nextEligible => 'Next eligible',
      WorkItemRecurrenceMissedWindowPolicy.singleStep => 'Single step',
      WorkItemRecurrenceMissedWindowPolicy.manualCatchUp => 'Manual catch-up',
    };
  }

  Future<void> _showNotificationPreferencesDialog(
    BuildContext context,
    WidgetRef ref, {
    required NotificationPreferences initial,
  }) async {
    var preferences = initial;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final isMuted =
              preferences.mutedUntil?.isAfter(DateTime.now()) ?? false;
          return AlertDialog(
            title: const Text('Notification preferences'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    value: preferences.enabled,
                    title: const Text('Enable reminders'),
                    onChanged: (value) {
                      setState(() {
                        preferences = preferences.copyWith(enabled: value);
                      });
                    },
                  ),
                  SwitchListTile(
                    value: preferences.remindOnDueDate,
                    title: const Text('Due date reminders'),
                    onChanged: (value) {
                      setState(() {
                        preferences =
                            preferences.copyWith(remindOnDueDate: value);
                      });
                    },
                  ),
                  SwitchListTile(
                    value: preferences.remindOnStartDate,
                    title: const Text('Start date reminders'),
                    onChanged: (value) {
                      setState(() {
                        preferences =
                            preferences.copyWith(remindOnStartDate: value);
                      });
                    },
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: preferences.dueReminderMinutesBefore,
                    decoration: const InputDecoration(
                      labelText: 'Due reminder lead time',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('At due time')),
                      DropdownMenuItem(
                          value: 15, child: Text('15 minutes before')),
                      DropdownMenuItem(
                          value: 30, child: Text('30 minutes before')),
                      DropdownMenuItem(value: 60, child: Text('1 hour before')),
                      DropdownMenuItem(
                          value: 240, child: Text('4 hours before')),
                      DropdownMenuItem(
                          value: 1440, child: Text('1 day before')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        preferences = preferences.copyWith(
                            dueReminderMinutesBefore: value);
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: preferences.startReminderMinutesBefore,
                    decoration: const InputDecoration(
                      labelText: 'Start reminder lead time',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('At start time')),
                      DropdownMenuItem(
                          value: 10, child: Text('10 minutes before')),
                      DropdownMenuItem(
                          value: 15, child: Text('15 minutes before')),
                      DropdownMenuItem(
                          value: 30, child: Text('30 minutes before')),
                      DropdownMenuItem(value: 60, child: Text('1 hour before')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        preferences = preferences.copyWith(
                            startReminderMinutesBefore: value);
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: preferences.defaultSnoozeMinutes,
                    decoration: const InputDecoration(
                      labelText: 'Default snooze duration',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 15, child: Text('15 minutes')),
                      DropdownMenuItem(value: 30, child: Text('30 minutes')),
                      DropdownMenuItem(value: 60, child: Text('1 hour')),
                      DropdownMenuItem(value: 240, child: Text('4 hours')),
                      DropdownMenuItem(value: 1440, child: Text('1 day')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        preferences =
                            preferences.copyWith(defaultSnoozeMinutes: value);
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mute reminders'),
                    subtitle: Text(
                      isMuted
                          ? 'Muted until ${preferences.mutedUntil!.toLocal().toIso8601String().replaceFirst('T', ' ').substring(0, 16)}'
                          : 'Not muted',
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        if (isMuted)
                          OutlinedButton(
                            onPressed: () {
                              setState(() {
                                preferences =
                                    preferences.copyWith(clearMutedUntil: true);
                              });
                            },
                            child: const Text('Clear'),
                          )
                        else
                          OutlinedButton(
                            onPressed: () {
                              setState(() {
                                preferences = preferences.copyWith(
                                  mutedUntil: DateTime.now()
                                      .add(const Duration(hours: 8)),
                                );
                              });
                            },
                            child: const Text('8h'),
                          ),
                      ],
                    ),
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
                onPressed: () async {
                  final ok = await _runGuardedAction(
                    context,
                    () => ref
                        .read(boardControllerProvider)
                        .updateNotificationPreferences(preferences),
                  );
                  if (ok && context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAutofillSettingsDialog(
    BuildContext context,
    WidgetRef ref, {
    required AutofillSettings initial,
  }) async {
    var settings = initial;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Autofill suggestions'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    value: settings.enabled,
                    title: const Text('Enable deterministic suggestions'),
                    onChanged: (value) {
                      setState(() {
                        settings = settings.copyWith(enabled: value);
                      });
                    },
                  ),
                  SwitchListTile(
                    value: settings.suggestType,
                    title: const Text('Suggest item type'),
                    onChanged: settings.enabled
                        ? (value) => setState(
                              () => settings =
                                  settings.copyWith(suggestType: value),
                            )
                        : null,
                  ),
                  SwitchListTile(
                    value: settings.suggestColumn,
                    title: const Text('Suggest column'),
                    onChanged: settings.enabled
                        ? (value) => setState(
                              () => settings =
                                  settings.copyWith(suggestColumn: value),
                            )
                        : null,
                  ),
                  SwitchListTile(
                    value: settings.suggestParent,
                    title: const Text('Suggest parent'),
                    onChanged: settings.enabled
                        ? (value) => setState(
                              () => settings =
                                  settings.copyWith(suggestParent: value),
                            )
                        : null,
                  ),
                  SwitchListTile(
                    value: settings.suggestTags,
                    title: const Text('Suggest tags'),
                    onChanged: settings.enabled
                        ? (value) => setState(
                              () => settings =
                                  settings.copyWith(suggestTags: value),
                            )
                        : null,
                  ),
                  SwitchListTile(
                    value: settings.suggestEstimate,
                    title: const Text('Suggest estimate'),
                    onChanged: settings.enabled
                        ? (value) => setState(
                              () => settings =
                                  settings.copyWith(suggestEstimate: value),
                            )
                        : null,
                  ),
                  SwitchListTile(
                    value: settings.suggestBoard,
                    title: const Text('Suggest triage board'),
                    onChanged: settings.enabled
                        ? (value) => setState(
                              () => settings =
                                  settings.copyWith(suggestBoard: value),
                            )
                        : null,
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
                onPressed: () async {
                  final ok = await _runGuardedAction(
                    context,
                    () => ref
                        .read(boardControllerProvider)
                        .updateAutofillSettings(settings),
                  );
                  if (ok && context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showReminderCenterSheet(BuildContext context, WidgetRef ref,
      [Map<String, int> accentColorValuesByItemKey =
          const <String, int>{}]) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final remindersAsync = ref.watch(boardActiveRemindersProvider);
          final currentBoardId = ref.watch(currentBoardIdProvider);
          final preferences =
              ref.watch(notificationPreferencesProvider).valueOrNull ??
                  const NotificationPreferences();

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: remindersAsync.when(
                loading: () => const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => SizedBox(
                  height: 220,
                  child: Center(
                    child: Text('Unable to load reminders: $error'),
                  ),
                ),
                data: (reminders) {
                  final reminderBoardIds = {
                    for (final reminder in reminders) reminder.item.boardId,
                  };
                  final reminderBoardSnapshots = {
                    for (final boardId in reminderBoardIds)
                      boardId: boardId == currentBoardId
                          ? ref.watch(boardStreamProvider).valueOrNull
                          : ref
                              .watch(boardSnapshotProvider(boardId))
                              .valueOrNull,
                  };
                  final resolvedAccentColorValuesByItemKey = {
                    ...accentColorValuesByItemKey,
                    ..._resolveItemAccentColorValues(
                      itemsByBoardId: {
                        for (final entry in reminderBoardSnapshots.entries)
                          if (entry.value != null)
                            entry.key: entry.value!.items,
                      },
                      settingsByBoardId: {
                        for (final entry in reminderBoardSnapshots.entries)
                          if (entry.value != null)
                            entry.key: entry.value!.board.validationSettings,
                      },
                    ),
                  };
                  final groupedReminders = _groupReminders(reminders);
                  final showBoardContext = reminders
                          .map((reminder) => reminder.item.boardId)
                          .toSet()
                          .length >
                      1;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Reminders (${reminders.length})',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _showNotificationPreferencesDialog(
                                context,
                                ref,
                                initial: preferences,
                              );
                            },
                            icon: const Icon(Icons.tune),
                            label: const Text('Preferences'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Flexible(
                        child: reminders.isEmpty
                            ? const Center(
                                child:
                                    Text('Nothing needs attention right now.'),
                              )
                            : ListView(
                                shrinkWrap: true,
                                children: [
                                  for (final section in _ReminderSection.values)
                                    if (groupedReminders[section]!
                                        .isNotEmpty) ...[
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 8,
                                          bottom: 8,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              _reminderSectionIcon(section),
                                              size: 18,
                                              color: section ==
                                                      _ReminderSection.overdue
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .error
                                                  : null,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _reminderSectionLabel(section),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '${groupedReminders[section]!.length}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                      for (final reminder
                                          in groupedReminders[section]!)
                                        Card(
                                          margin:
                                              const EdgeInsets.only(bottom: 10),
                                          child: InkWell(
                                            onTap: () => _openReminderDetails(
                                              context,
                                              ref,
                                              reminder: reminder,
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Container(
                                                    key: ValueKey(
                                                      'reminder-item-accent-${reminder.item.boardId}-${reminder.item.itemId}',
                                                    ),
                                                    width: 4,
                                                    height: 74,
                                                    decoration: BoxDecoration(
                                                      color: (() {
                                                        final accentColorValue =
                                                            resolvedAccentColorValuesByItemKey[
                                                                _itemAccentKey(
                                                          boardId: reminder
                                                              .item.boardId,
                                                          itemId: reminder
                                                              .item.itemId,
                                                        )];
                                                        return accentColorValue ==
                                                                null
                                                            ? Theme.of(context)
                                                                .colorScheme
                                                                .outlineVariant
                                                            : Color(
                                                                accentColorValue,
                                                              );
                                                      })(),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        4,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          reminder.item.title,
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .titleSmall,
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Text(
                                                          '${_reminderKindLabel(reminder.kind)} • ${_reminderAttentionLine(reminder, showBoardContext: showBoardContext)}',
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodySmall,
                                                        ),
                                                        const SizedBox(
                                                          height: 10,
                                                        ),
                                                        Wrap(
                                                          spacing: 8,
                                                          runSpacing: 8,
                                                          children: [
                                                            if (_canQuickCompleteReminder(
                                                              reminder,
                                                            ))
                                                              FilledButton
                                                                  .tonal(
                                                                onPressed: () =>
                                                                    _handleReminderDone(
                                                                  context,
                                                                  ref,
                                                                  reminder:
                                                                      reminder,
                                                                ),
                                                                child:
                                                                    const Text(
                                                                  'Done',
                                                                ),
                                                              )
                                                            else
                                                              OutlinedButton(
                                                                onPressed: () =>
                                                                    _openReminderDetails(
                                                                  context,
                                                                  ref,
                                                                  reminder:
                                                                      reminder,
                                                                ),
                                                                child:
                                                                    const Text(
                                                                  'Open',
                                                                ),
                                                              ),
                                                            OutlinedButton(
                                                              onPressed: () =>
                                                                  _runGuardedAction(
                                                                context,
                                                                () => ref
                                                                    .read(
                                                                      boardControllerProvider,
                                                                    )
                                                                    .snoozeReminder(
                                                                      reminderId:
                                                                          reminder
                                                                              .reminderId,
                                                                    ),
                                                              ),
                                                              child: const Text(
                                                                'Snooze',
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                ],
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showSystemNotificationsSheet(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final notices = ref.watch(workspaceVisibleSystemNoticesProvider);

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Notifications (${notices.length})',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: notices.isEmpty
                        ? const Center(
                            child: Text('Nothing needs attention right now.'),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: notices.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final notice = notices[index];
                              final attentionNotice =
                                  WorkspaceAttentionNotice.fromSystem(notice);
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            notice.kind ==
                                                    WorkspaceSystemNoticeKind
                                                        .permissionDenied
                                                ? Icons.lock_outline
                                                : Icons.sync_problem,
                                            color: notice.severity ==
                                                    WorkspaceAttentionSeverity
                                                        .critical
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .error
                                                : null,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  notice.title,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall,
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  notice.message,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall,
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Dismiss notification',
                                            onPressed: () {
                                              ref
                                                  .read(boardControllerProvider)
                                                  .dismissSystemNotice(
                                                    noticeId: notice.noticeId,
                                                    stateToken:
                                                        notice.stateToken,
                                                  );
                                            },
                                            icon: const Icon(Icons.close),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          FilledButton.tonal(
                                            onPressed: () =>
                                                _runWorkspaceNoticeAction(
                                              context,
                                              ref,
                                              notice: attentionNotice,
                                              action: notice.primaryAction,
                                            ),
                                            child: Text(
                                              notice.primaryAction.label,
                                            ),
                                          ),
                                          if (notice.secondaryAction != null)
                                            OutlinedButton(
                                              onPressed: () =>
                                                  _runWorkspaceNoticeAction(
                                                context,
                                                ref,
                                                notice: attentionNotice,
                                                action: notice.secondaryAction!,
                                              ),
                                              child: Text(
                                                notice.secondaryAction!.label,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
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
      ),
    );
  }

  String _densityLabel(BoardCardDensity density) {
    return switch (density) {
      BoardCardDensity.comfortable => 'Comfortable',
      BoardCardDensity.compact => 'Compact',
    };
  }

  static const List<BoardPlanningView> _quickWorkspaceViews = [
    BoardPlanningView.kanban,
    BoardPlanningView.hierarchy,
    BoardPlanningView.calendar,
  ];

  BoardPlanningView _nextPlanningView(BoardPlanningView current) {
    final views = _quickWorkspaceViews;
    final index = views.indexOf(current);
    if (index < 0) return BoardPlanningView.kanban;
    return views[(index + 1) % views.length];
  }

  Future<void> _showWorkspaceViewPicker(
    BuildContext context,
    WidgetRef ref, {
    required BoardPlanningView current,
  }) async {
    final selected = await showModalBottomSheet<BoardPlanningView>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Workspace view',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final view in _quickWorkspaceViews)
                    ChoiceChip(
                      avatar: Icon(
                        boardPlanningViewIcon(view),
                        size: 18,
                      ),
                      label: Text(boardPlanningViewLabel(view)),
                      selected: view == current,
                      onSelected: (_) => Navigator.of(context).pop(view),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || selected == current) return;
    ref.read(boardControllerProvider).setPlanningView(selected);
  }

  int _activeWorkspaceFilterCount({
    required BoardPlanningView planningView,
    required Set<WorkItemType> typeFilters,
    required BoardItemStateFilter stateFilter,
    required String tagFilter,
    required bool showOverdueOnly,
    required bool showDueSoonOnly,
    required bool showArchivedOnly,
    required Set<BoardCalendarMarkerKind> calendarVisibleKinds,
    required bool showCalendarUnscheduled,
  }) {
    var count = 0;
    if (typeFilters.isNotEmpty) count++;
    if (stateFilter != BoardItemStateFilter.any) count++;
    if (tagFilter.trim().isNotEmpty) count++;
    if (showOverdueOnly) count++;
    if (showDueSoonOnly) count++;
    if (showArchivedOnly) count++;
    if (planningView == BoardPlanningView.calendar) {
      const defaultKinds = <BoardCalendarMarkerKind>{
        BoardCalendarMarkerKind.start,
        BoardCalendarMarkerKind.targetEnd,
        BoardCalendarMarkerKind.due,
      };
      if (calendarVisibleKinds.length != defaultKinds.length ||
          !calendarVisibleKinds.containsAll(defaultKinds)) {
        count++;
      }
      if (!showCalendarUnscheduled) count++;
    }
    return count;
  }

  Future<void> _triggerSyncNow(BuildContext context, WidgetRef ref) async {
    final syncUiState = ref.read(syncUiStateProvider);
    if (syncUiState.isSyncing) return;
    try {
      final report = await ref
          .read(boardControllerProvider)
          .syncNow(ignoreRetrySchedule: true);
      if (!context.mounted) return;
      final deniedSegment = report.permissionDenied > 0
          ? ', ${report.permissionDenied} permission denied'
          : '';
      _showActionFeedback(
        context,
        'Sync complete: ${report.processed} processed, ${report.failed} failed$deniedSegment',
        severity: WorkspaceFeedbackSeverity.success,
      );
    } catch (error) {
      if (!context.mounted) return;
      _showActionFeedback(context, 'Sync failed: $error');
    }
  }

  Future<void> _showWorkspaceFiltersSheet(
    BuildContext context,
    WidgetRef ref, {
    required BoardPlanningView planningView,
    required Set<WorkItemType> typeFilters,
    required BoardItemStateFilter stateFilter,
    required String tagFilter,
    required bool showOverdueOnly,
    required bool showDueSoonOnly,
    required bool showArchivedOnly,
  }) async {
    var selectedTypeFilters = <WorkItemType>{...typeFilters};
    var selectedView = planningView;
    var selectedState = stateFilter;
    var selectedTag = tagFilter;
    var selectedOverdue = showOverdueOnly;
    var selectedDueSoon = showDueSoonOnly;
    var selectedArchived = showArchivedOnly;
    var selectedCalendarKinds = <BoardCalendarMarkerKind>{
      ...ref.read(boardCalendarVisibleDateKindsProvider),
    };
    var selectedShowCalendarUnscheduled =
        ref.read(boardCalendarShowUnscheduledProvider);
    const defaultCalendarKinds = <BoardCalendarMarkerKind>{
      BoardCalendarMarkerKind.start,
      BoardCalendarMarkerKind.targetEnd,
      BoardCalendarMarkerKind.due,
    };

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Filters',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Text('View', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final view in BoardPlanningView.values)
                          Tooltip(
                            message: boardPlanningViewLabel(view),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () {
                                setState(() => selectedView = view);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: selectedView == view
                                      ? Theme.of(context)
                                          .colorScheme
                                          .secondaryContainer
                                      : null,
                                  border: Border.all(
                                    color: selectedView == view
                                        ? Theme.of(context)
                                            .colorScheme
                                            .secondary
                                        : Theme.of(context)
                                            .colorScheme
                                            .outlineVariant,
                                  ),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Icon(
                                  boardPlanningViewIcon(view),
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Type', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final type in WorkItemType.values)
                          FilterChip(
                            label: Text(_typeFilterLabel(type)),
                            selected: selectedTypeFilters.contains(type),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  selectedTypeFilters.add(type);
                                } else {
                                  selectedTypeFilters.remove(type);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    if (selectedTypeFilters.isEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'No type selected means all item types are shown.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    DropdownButtonFormField<BoardItemStateFilter>(
                      initialValue: selectedState,
                      decoration: const InputDecoration(labelText: 'State'),
                      items: [
                        for (final value in BoardItemStateFilter.values)
                          DropdownMenuItem(
                            value: value,
                            child: Text(_stateFilterLabel(value)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => selectedState = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      initialValue: selectedTag,
                      decoration: const InputDecoration(
                        labelText: 'Tag contains',
                        hintText: 'e.g. ux',
                      ),
                      onChanged: (value) => selectedTag = value,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('Overdue'),
                          selected: selectedOverdue,
                          onSelected: (value) {
                            setState(() {
                              selectedOverdue = value;
                              if (value) selectedDueSoon = false;
                            });
                          },
                        ),
                        FilterChip(
                          label: const Text('Due ≤ 7d'),
                          selected: selectedDueSoon,
                          onSelected: (value) {
                            setState(() {
                              selectedDueSoon = value;
                              if (value) selectedOverdue = false;
                            });
                          },
                        ),
                        FilterChip(
                          label: const Text('Archived'),
                          selected: selectedArchived,
                          onSelected: (value) {
                            setState(() => selectedArchived = value);
                          },
                        ),
                      ],
                    ),
                    if (selectedView == BoardPlanningView.calendar) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Calendar',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final kind in BoardCalendarMarkerKind.values)
                            FilterChip(
                              label: Text(
                                switch (kind) {
                                  BoardCalendarMarkerKind.start => 'Start',
                                  BoardCalendarMarkerKind.targetEnd => 'Target',
                                  BoardCalendarMarkerKind.due => 'Due',
                                },
                              ),
                              selected: selectedCalendarKinds.contains(kind),
                              onSelected: (value) {
                                setState(() {
                                  if (value) {
                                    selectedCalendarKinds.add(kind);
                                  } else if (selectedCalendarKinds.length > 1) {
                                    selectedCalendarKinds.remove(kind);
                                  }
                                });
                              },
                            ),
                          FilterChip(
                            label: const Text('Unscheduled'),
                            selected: selectedShowCalendarUnscheduled,
                            onSelected: (value) {
                              setState(() {
                                selectedShowCalendarUnscheduled = value;
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            final currentCalendarSubview =
                                ref.read(boardCalendarSubviewProvider);
                            ref
                                .read(boardVisibilityFilterProvider.notifier)
                                .state = <WorkItemType>{};
                            ref
                                .read(boardItemStateFilterProvider.notifier)
                                .state = BoardItemStateFilter.any;
                            ref.read(boardTagFilterProvider.notifier).state =
                                '';
                            ref.read(showOverdueOnlyProvider.notifier).state =
                                false;
                            ref.read(showDueSoonOnlyProvider.notifier).state =
                                false;
                            ref.read(showArchivedOnlyProvider.notifier).state =
                                false;
                            if (planningView == BoardPlanningView.calendar) {
                              ref
                                  .read(
                                    boardCalendarVisibleDateKindsProvider
                                        .notifier,
                                  )
                                  .state = defaultCalendarKinds;
                              ref
                                  .read(
                                    boardCalendarShowUnscheduledProvider
                                        .notifier,
                                  )
                                  .state = true;
                              unawaited(
                                ref
                                    .read(boardControllerProvider)
                                    .updateCalendarPreferences(
                                      BoardCalendarPreferences(
                                        lastSubview: currentCalendarSubview,
                                        visibleDateKinds: defaultCalendarKinds,
                                        showUnscheduled: true,
                                      ),
                                    ),
                              );
                            }
                            Navigator.of(context).pop();
                          },
                          child: const Text('Reset'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () {
                            ref
                                .read(boardControllerProvider)
                                .setPlanningView(selectedView);
                            ref
                                .read(boardVisibilityFilterProvider.notifier)
                                .state = selectedTypeFilters.toSet();
                            ref
                                .read(boardItemStateFilterProvider.notifier)
                                .state = selectedState;
                            ref.read(boardTagFilterProvider.notifier).state =
                                selectedTag.trim();
                            ref.read(showOverdueOnlyProvider.notifier).state =
                                selectedOverdue;
                            ref.read(showDueSoonOnlyProvider.notifier).state =
                                selectedDueSoon;
                            ref.read(showArchivedOnlyProvider.notifier).state =
                                selectedArchived;
                            final calendarKinds = selectedCalendarKinds.toSet();
                            final calendarSubview =
                                ref.read(boardCalendarSubviewProvider);
                            ref
                                .read(
                                  boardCalendarVisibleDateKindsProvider
                                      .notifier,
                                )
                                .state = calendarKinds;
                            ref
                                .read(
                                  boardCalendarShowUnscheduledProvider.notifier,
                                )
                                .state = selectedShowCalendarUnscheduled;
                            unawaited(
                              ref
                                  .read(boardControllerProvider)
                                  .updateCalendarPreferences(
                                    BoardCalendarPreferences(
                                      lastSubview: calendarSubview,
                                      visibleDateKinds: calendarKinds,
                                      showUnscheduled:
                                          selectedShowCalendarUnscheduled,
                                    ),
                                  ),
                            );
                            Navigator.of(context).pop();
                          },
                          child: const Text('Apply'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showSavePresetDialog(
    BuildContext context,
    WidgetRef ref, {
    BoardFilterPreset? existing,
  }) async {
    var presetName = existing?.name ?? '';
    final submittedName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Save filter preset' : 'Rename preset'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Preset name',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => presetName = value,
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
              final name = presetName.trim();
              if (name.isEmpty) return;
              Navigator.of(context).pop(name);
            },
            child: Text(existing == null ? 'Save' : 'Rename'),
          ),
        ],
      ),
    );
    final name = submittedName?.trim();
    if (name == null || name.isEmpty) return;

    if (existing == null) {
      await _runGuardedAction(
        context,
        () => ref
            .read(boardControllerProvider)
            .saveCurrentFilterPreset(name: name),
      );
    } else {
      await _runGuardedAction(
        context,
        () => ref.read(boardControllerProvider).renameFilterPreset(
              preset: existing,
              name: name,
            ),
      );
    }
  }

  Future<void> _showFilterPresetsSheet(
    BuildContext context,
    WidgetRef ref, {
    required List<BoardFilterPreset> presets,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filter presets',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await _showSavePresetDialog(context, ref);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Save current'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (presets.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No presets yet. Save your current filters.'),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: presets.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final preset = presets[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(preset.name),
                        subtitle: Text(
                          'Updated ${preset.updatedAt.toLocal().toIso8601String().replaceFirst('T', ' ').substring(0, 16)}',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) async {
                            switch (value) {
                              case 'apply':
                                await _runGuardedAction(
                                  context,
                                  () => ref
                                      .read(boardControllerProvider)
                                      .applyFilterPreset(preset),
                                );
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                }
                                break;
                              case 'update':
                                await _runGuardedAction(
                                  context,
                                  () => ref
                                      .read(boardControllerProvider)
                                      .saveCurrentFilterPreset(
                                        name: preset.name,
                                        presetId: preset.presetId,
                                      ),
                                );
                                break;
                              case 'rename':
                                await _showSavePresetDialog(
                                  context,
                                  ref,
                                  existing: preset,
                                );
                                break;
                              case 'delete':
                                final shouldDelete =
                                    await _confirmDestructiveAction(
                                  context,
                                  title: 'Delete preset?',
                                  message:
                                      'Delete "${preset.name}" filter preset?',
                                  confirmLabel: 'Delete',
                                );
                                if (!shouldDelete) break;
                                await _runGuardedAction(
                                  context,
                                  () => ref
                                      .read(boardControllerProvider)
                                      .deleteFilterPreset(preset.presetId),
                                );
                                break;
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'apply',
                              child: Text('Apply preset'),
                            ),
                            PopupMenuItem(
                              value: 'update',
                              child: Text('Update from current filters'),
                            ),
                            PopupMenuItem(
                              value: 'rename',
                              child: Text('Rename'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                        onTap: () async {
                          await _runGuardedAction(
                            context,
                            () => ref
                                .read(boardControllerProvider)
                                .applyFilterPreset(preset),
                          );
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolsSectionHeading(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  Future<void> _showWorkspaceToolsSurface(BuildContext parentContext) async {
    final useDesktopSheet = MediaQuery.sizeOf(parentContext).width >= 960;

    Future<void> closeThen(
      BuildContext sheetContext,
      Future<void> Function(WidgetRef ref) action,
      WidgetRef ref,
    ) async {
      Navigator.of(sheetContext).pop();
      await Future<void>.delayed(Duration.zero);
      if (!parentContext.mounted) return;
      await action(ref);
    }

    Widget buildSurface(BuildContext surfaceContext) {
      return Consumer(
        builder: (context, ref, _) {
          final workspaceSurface = ref.watch(boardWorkspaceSurfaceProvider);
          final boardSnapshot = ref.watch(boardStreamProvider).valueOrNull;
          final inboxCount =
              boardSnapshot?.items.where((item) => item.isInbox).length ?? 0;
          final reminders =
              ref.watch(boardActiveRemindersProvider).valueOrNull ??
                  const <BoardReminderAlert>[];
          final systemNotices =
              ref.watch(workspaceVisibleSystemNoticesProvider);
          final autofillSettings =
              ref.watch(autofillSettingsProvider).valueOrNull ??
                  const AutofillSettings();
          final filterPresets =
              ref.watch(boardFilterPresetsProvider).valueOrNull ??
                  const <BoardFilterPreset>[];
          final pendingCount =
              ref.watch(pendingOutboxCountProvider).valueOrNull ?? 0;
          final outboxStatus = ref.watch(outboxStatusProvider).valueOrNull;
          final syncUiState = ref.watch(syncUiStateProvider);
          final cardDensity = ref.watch(boardCardDensityProvider);
          final focusedItemId = ref.watch(focusedItemIdProvider);
          final focusModeEnabled = ref.watch(focusModeEnabledProvider);
          final permissionProfile = ref.watch(boardPermissionProfileProvider);
          final canJoinInvite =
              permissionProfile?.has(BoardCapability.joinInvite) ?? false;

          final syncSummary = switch ((syncUiState.isSyncing, pendingCount)) {
            (true, _) => 'Sync in progress',
            (false, 0) => 'No pending sync operations',
            (false, _) => '$pendingCount pending changes',
          };
          final syncSubtitle = outboxStatus?.latestError == null
              ? syncSummary
              : '$syncSummary\n${outboxStatus!.latestError}';

          final content = SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Workspace tools',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (!useDesktopSheet) const CloseButton(),
                      ],
                    ),
                  ),
                  _toolsSectionHeading(context, 'Triage'),
                  ListTile(
                    leading: const Icon(Icons.inbox_outlined),
                    title: Text(
                      workspaceSurface == BoardWorkspaceSurface.inbox
                          ? 'Show board'
                          : 'Open inbox',
                    ),
                    subtitle: Text(
                      inboxCount == 0
                          ? 'No inbox items waiting'
                          : '$inboxCount item(s) waiting to be triaged',
                    ),
                    trailing: inboxCount > 0
                        ? Badge(
                            label: Text('$inboxCount'),
                            child: const Icon(Icons.chevron_right),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: () {
                      ref.read(boardWorkspaceSurfaceProvider.notifier).state =
                          workspaceSurface == BoardWorkspaceSurface.inbox
                              ? BoardWorkspaceSurface.board
                              : BoardWorkspaceSurface.inbox;
                      Navigator.of(context).pop();
                    },
                  ),
                  _toolsSectionHeading(context, 'Workspace'),
                  ListTile(
                    leading: const Icon(Icons.notifications_none_outlined),
                    title: const Text('Reminders'),
                    subtitle: Text(
                      reminders.isEmpty
                          ? 'No active reminders'
                          : '${reminders.length} reminder(s) need attention',
                    ),
                    trailing: reminders.isNotEmpty
                        ? Badge(
                            label: Text('${reminders.length}'),
                            child: const Icon(Icons.chevron_right),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: () => closeThen(
                      context,
                      (ref) => _showReminderCenterSheet(parentContext, ref),
                      ref,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('Notifications'),
                    subtitle: Text(
                      systemNotices.isEmpty
                          ? 'No persistent notices right now'
                          : '${systemNotices.length} notification(s) need attention',
                    ),
                    trailing: systemNotices.isNotEmpty
                        ? Badge(
                            label: Text('${systemNotices.length}'),
                            child: const Icon(Icons.chevron_right),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: () => closeThen(
                      context,
                      (ref) =>
                          _showSystemNotificationsSheet(parentContext, ref),
                      ref,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.bookmarks_outlined),
                    title: const Text('Filter presets'),
                    subtitle: Text(
                      filterPresets.isEmpty
                          ? 'Save and reuse filter combinations'
                          : '${filterPresets.length} preset(s) saved',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => closeThen(
                      context,
                      (ref) => _showFilterPresetsSheet(
                        parentContext,
                        ref,
                        presets: filterPresets,
                      ),
                      ref,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.auto_awesome_outlined),
                    title: const Text('Autofill suggestions'),
                    subtitle: Text(
                      autofillSettings.enabled
                          ? 'Deterministic suggestions enabled'
                          : 'Suggestions are currently off',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => closeThen(
                      context,
                      (ref) => _showAutofillSettingsDialog(
                        parentContext,
                        ref,
                        initial: autofillSettings,
                      ),
                      ref,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      'Card density',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final density in BoardCardDensity.values)
                          ChoiceChip(
                            label: Text(_densityLabel(density)),
                            selected: cardDensity == density,
                            onSelected: (_) {
                              ref
                                  .read(boardCardDensityProvider.notifier)
                                  .state = density;
                            },
                          ),
                      ],
                    ),
                  ),
                  SwitchListTile.adaptive(
                    secondary: Icon(
                      focusModeEnabled
                          ? Icons.filter_center_focus
                          : Icons.filter_center_focus_outlined,
                    ),
                    title: const Text('Focus mode'),
                    subtitle: Text(
                      focusedItemId == null
                          ? 'Select an item first to enable focus mode'
                          : 'Show selected item context only',
                    ),
                    value: focusModeEnabled,
                    onChanged: focusedItemId == null
                        ? null
                        : (value) {
                            ref.read(focusModeEnabledProvider.notifier).state =
                                value;
                          },
                  ),
                  if (focusedItemId != null)
                    ListTile(
                      leading: const Icon(Icons.center_focus_weak),
                      title: const Text('Clear focus'),
                      onTap: () {
                        ref.read(boardControllerProvider).clearFocusedItem();
                        Navigator.of(context).pop();
                      },
                    ),
                  _toolsSectionHeading(context, 'Sync'),
                  ListTile(
                    leading: syncUiState.isSyncing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    title: const Text('Pending sync operations'),
                    subtitle: Text(syncSubtitle),
                    isThreeLine: outboxStatus?.latestError != null,
                    trailing: pendingCount > 0
                        ? Badge(
                            label: Text('$pendingCount'),
                            child: const Icon(Icons.chevron_right),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: () => closeThen(
                      context,
                      (ref) => _showOutboxSheet(parentContext, ref),
                      ref,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.cloud_upload_outlined),
                    title: const Text('Sync now'),
                    subtitle: Text(
                      syncUiState.isSyncing
                          ? 'Already syncing'
                          : 'Push pending changes now',
                    ),
                    enabled: !syncUiState.isSyncing,
                    onTap: syncUiState.isSyncing
                        ? null
                        : () => closeThen(
                              context,
                              (ref) => _triggerSyncNow(parentContext, ref),
                              ref,
                            ),
                  ),
                  _toolsSectionHeading(context, 'Account / Access'),
                  if (canJoinInvite)
                    ListTile(
                      leading: const Icon(Icons.how_to_reg_outlined),
                      title: const Text('Accept board invite'),
                      onTap: () => closeThen(
                        context,
                        (ref) => _runGuardedAction(
                          parentContext,
                          () =>
                              ref.read(boardControllerProvider).acceptInvite(),
                        ),
                        ref,
                      ),
                    ),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Sign out'),
                    onTap: () => closeThen(
                      context,
                      (ref) => ref.read(authControllerProvider).signOut(),
                      ref,
                    ),
                  ),
                ],
              ),
            ),
          );

          if (!useDesktopSheet) {
            return SafeArea(child: content);
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 72, 16, 16),
            child: Align(
              alignment: Alignment.topRight,
              child: Material(
                elevation: 8,
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(28),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 380,
                    maxHeight: 640,
                  ),
                  child: content,
                ),
              ),
            ),
          );
        },
      );
    }

    if (useDesktopSheet) {
      await showDialog<void>(
        context: parentContext,
        barrierColor: Colors.black45,
        builder: buildSurface,
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: parentContext,
      showDragHandle: true,
      isScrollControlled: true,
      builder: buildSurface,
    );
  }

  bool _matchesFilter(WorkItem item, Set<WorkItemType> filters) {
    return filters.isEmpty || filters.contains(item.type);
  }

  bool _matchesStateFilter({
    required WorkItem item,
    required BoardItemStateFilter stateFilter,
    required Map<String, BoardColumn> columnsById,
  }) {
    if (stateFilter == BoardItemStateFilter.any) return true;

    final now = DateTime.now();
    final dueAt = item.dueAt;
    final horizon = now.add(const Duration(days: 7));
    final column = columnsById[item.columnId];
    final isDone = item.completedAt != null || column?.isDoneState == true;
    final isCancelled = column?.isCancelledState == true;
    final isBlocked = column?.isBlockedState == true;
    final isUrgent = column?.kind == BoardColumnKind.urgent;
    final isOverdue =
        dueAt != null && item.completedAt == null && dueAt.isBefore(now);
    final isDueSoon = dueAt != null &&
        item.completedAt == null &&
        !dueAt.isBefore(now) &&
        !dueAt.isAfter(horizon);

    return switch (stateFilter) {
      BoardItemStateFilter.any => true,
      BoardItemStateFilter.active => !isDone && !isCancelled,
      BoardItemStateFilter.done => isDone,
      BoardItemStateFilter.blocked => isBlocked,
      BoardItemStateFilter.cancelled => isCancelled,
      BoardItemStateFilter.urgent => isUrgent,
      BoardItemStateFilter.overdue => isOverdue,
      BoardItemStateFilter.dueSoon => isDueSoon,
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
    return BoardValidationPolicy.isAllowedParentType(
      childType: child,
      parentType: parent,
    );
  }

  List<WorkItem> _parentCandidatesForType({
    required WorkItemType childType,
    required List<WorkItem> allItems,
    String? currentItemId,
    String? preserveParentId,
  }) {
    final candidates = BoardValidationPolicy.allowedParentCandidates(
      childType: childType,
      allItems: allItems,
      itemId: currentItemId,
    );
    if (preserveParentId == null) return candidates;
    if (candidates.any((item) => item.itemId == preserveParentId)) {
      return candidates;
    }
    final preserved = allItems
        .where((item) => item.itemId == preserveParentId)
        .cast<WorkItem?>()
        .firstWhere((_) => true, orElse: () => null);
    if (preserved == null) return candidates;
    return [preserved, ...candidates];
  }

  String _parentCandidateLabel({
    required WorkItem child,
    required WorkItem candidate,
  }) {
    final isInvalidCurrent = !_isRecommendedParentType(
      child: child.type,
      parent: candidate.type,
    );
    final suffix = isInvalidCurrent ? ' (current, invalid)' : '';
    return '${_workItemTypeLabel(candidate.type)}: ${candidate.title}$suffix';
  }

  String _workItemTypeLabel(WorkItemType type) {
    return switch (type) {
      WorkItemType.goal => 'Goal',
      WorkItemType.project => 'Project',
      WorkItemType.task => 'Task',
      WorkItemType.action => 'Action',
    };
  }

  bool _requiresParentForType({
    required BoardValidationSettings settings,
    required WorkItemType type,
  }) {
    return switch (type) {
      WorkItemType.goal => false,
      WorkItemType.project => settings.requireParentForProjects,
      WorkItemType.task => settings.requireParentForTasks,
      WorkItemType.action => settings.requireParentForActions,
    };
  }

  bool _isInProgressColumnForCreate(
    List<BoardColumn> columns,
    String columnId,
  ) {
    final column = columns
        .where((entry) => entry.columnId == columnId)
        .cast<BoardColumn?>()
        .firstWhere((_) => true, orElse: () => null);
    if (column == null) return false;
    final normalized = WorkflowSemanticsPolicy.withLegacyInference(column);
    return normalized.kind == BoardColumnKind.inProgress;
  }

  DateTime? _defaultCreateStartAt(
    List<BoardColumn> columns,
    String columnId,
  ) {
    if (!_isInProgressColumnForCreate(columns, columnId)) return null;
    return DateTime.now();
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
    required Set<WorkItemType> filters,
    required BoardItemStateFilter stateFilter,
    required bool focusModeEnabled,
    required Set<String>? focusRelatedItemIds,
    required String textQuery,
    required String tagFilter,
    required Map<String, BoardColumn> columnsById,
    required bool showOverdueOnly,
    required bool showDueSoonOnly,
    required bool showArchivedOnly,
  }) {
    if (item.isInbox) return false;
    if (!_matchesFilter(item, filters)) return false;
    if (!_matchesStateFilter(
      item: item,
      stateFilter: stateFilter,
      columnsById: columnsById,
    )) {
      return false;
    }
    if (tagFilter.trim().isNotEmpty) {
      final normalized = tagFilter.trim().toLowerCase();
      final hasTag =
          item.tags.any((tag) => tag.toLowerCase().contains(normalized));
      if (!hasTag) return false;
    }
    if (textQuery.trim().isNotEmpty &&
        !item.title.toLowerCase().contains(textQuery.trim().toLowerCase())) {
      return false;
    }
    if (showOverdueOnly) {
      final dueAt = item.dueAt;
      final isOverdue = dueAt != null &&
          item.completedAt == null &&
          dueAt.isBefore(DateTime.now());
      if (!isOverdue) return false;
    }
    if (showDueSoonOnly) {
      final dueAt = item.dueAt;
      final now = DateTime.now();
      final horizon = now.add(const Duration(days: 7));
      final isDueSoon = dueAt != null &&
          item.completedAt == null &&
          !dueAt.isBefore(now) &&
          !dueAt.isAfter(horizon);
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
    required Set<WorkItemType> filters,
    required BoardItemStateFilter stateFilter,
    required bool focusModeEnabled,
    required Set<String>? focusRelatedItemIds,
    required String textQuery,
    required String tagFilter,
    required Map<String, BoardColumn> columnsById,
    required bool showOverdueOnly,
    required bool showDueSoonOnly,
    required bool showArchivedOnly,
  }) {
    final visible = items.where((i) {
      if (i.columnId != columnId) return false;
      return _isVisibleInCurrentModes(
        item: i,
        filters: filters,
        stateFilter: stateFilter,
        focusModeEnabled: focusModeEnabled,
        focusRelatedItemIds: focusRelatedItemIds,
        textQuery: textQuery,
        tagFilter: tagFilter,
        columnsById: columnsById,
        showOverdueOnly: showOverdueOnly,
        showDueSoonOnly: showDueSoonOnly,
        showArchivedOnly: showArchivedOnly,
      );
    }).toList();
    visible.sort(_compareVisibleItems);

    return visible;
  }

  int _compareVisibleItems(WorkItem a, WorkItem b) {
    int urgencyRank(WorkItem item) {
      final now = DateTime.now();
      if (item.completedAt != null) return 3;
      if (item.dueAt != null && item.dueAt!.isBefore(now)) return 0;
      if (item.dueAt != null) return 1;
      return 2;
    }

    final bySortOrder = a.sortOrder.compareTo(b.sortOrder);
    if (bySortOrder != 0) return bySortOrder;

    final urgency = urgencyRank(a).compareTo(urgencyRank(b));
    if (urgency != 0) return urgency;

    if (a.dueAt != null && b.dueAt != null) {
      final due = a.dueAt!.compareTo(b.dueAt!);
      if (due != 0) return due;
    }

    final updated = b.updatedAt.compareTo(a.updatedAt);
    if (updated != 0) return updated;

    final byBoard = a.boardId.compareTo(b.boardId);
    if (byBoard != 0) return byBoard;

    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  String _multiBoardKanbanLaneKey(BoardColumn column) {
    final normalized = WorkflowSemanticsPolicy.withLegacyInference(column);
    final compactName =
        normalized.name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return 'lane:$compactName:${normalized.isDoneState}:${normalized.isBlockedState}:${normalized.isCancelledState}';
  }

  String _hierarchyNodeKey({
    required String boardId,
    required String itemId,
  }) {
    return '$boardId::$itemId';
  }

  String _hierarchyNodeKeyForItem(WorkItem item) {
    return _hierarchyNodeKey(boardId: item.boardId, itemId: item.itemId);
  }

  Future<void> _confirmDeleteColumn(
    BuildContext context,
    WidgetRef ref, {
    required String columnId,
    required String name,
    required bool canDelete,
  }) async {
    if (!canDelete) {
      _showActionFeedback(context, 'You must keep at least one column.');
      return;
    }

    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete column?'),
            content:
                Text('Delete "$name"? Items will be moved to another column.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Delete')),
            ],
          ),
        ) ??
        false;

    if (!shouldDelete) return;
    await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).deleteColumn(columnId),
    );
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
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel')),
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
    await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).createColumn(name),
    );
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
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel')),
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
    await _runGuardedAction(
      context,
      () => ref
          .read(boardControllerProvider)
          .renameColumn(columnId: columnId, name: name),
    );
  }

  Future<void> _showCreateBoardDialog(
      BuildContext context, WidgetRef ref) async {
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

    await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).createBoard(name),
    );
  }

  String _roleLabel(BoardRole role) {
    final name = role.name;
    return '${name[0].toUpperCase()}${name.substring(1)}';
  }

  Future<void> _showValidationSettingsDialog(
    BuildContext context,
    WidgetRef ref, {
    required BoardValidationSettings initial,
  }) async {
    var settings = initial;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Validation settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      value: settings.requireParentForProjects,
                      title: const Text('Require parent for projects'),
                      onChanged: (value) {
                        setState(() {
                          settings = settings.copyWith(
                            requireParentForProjects: value,
                          );
                        });
                      },
                    ),
                    SwitchListTile(
                      value: settings.requireParentForTasks,
                      title: const Text('Require parent for tasks'),
                      onChanged: (value) {
                        setState(() {
                          settings = settings.copyWith(
                            requireParentForTasks: value,
                          );
                        });
                      },
                    ),
                    SwitchListTile(
                      value: settings.requireParentForActions,
                      title: const Text('Require parent for actions'),
                      onChanged: (value) {
                        setState(() {
                          settings = settings.copyWith(
                            requireParentForActions: value,
                          );
                        });
                      },
                    ),
                    SwitchListTile(
                      value: settings.enforceParentTypeOrder,
                      title: const Text('Enforce parent type order'),
                      subtitle: const Text(
                        'Parent must be a higher-level type than child.',
                      ),
                      onChanged: (value) {
                        setState(() {
                          settings = settings.copyWith(
                            enforceParentTypeOrder: value,
                          );
                        });
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
                  onPressed: () async {
                    final ok = await _runGuardedAction(
                      context,
                      () => ref
                          .read(boardControllerProvider)
                          .updateBoardValidationSettings(settings),
                    );
                    if (ok && context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _workflowKindLabel(BoardColumnKind kind) {
    return switch (kind) {
      BoardColumnKind.planning => 'Planning',
      BoardColumnKind.backlog => 'Backlog',
      BoardColumnKind.ready => 'Ready',
      BoardColumnKind.inProgress => 'In Progress',
      BoardColumnKind.blocked => 'Blocked',
      BoardColumnKind.urgent => 'Urgent',
      BoardColumnKind.review => 'Review',
      BoardColumnKind.done => 'Done',
      BoardColumnKind.cancelled => 'Cancelled',
      BoardColumnKind.custom => 'Custom',
    };
  }

  Future<void> _showWorkflowSettingsDialog(
    BuildContext context,
    WidgetRef ref, {
    required BoardSnapshot snapshot,
  }) async {
    var workflow = snapshot.board.workflowSettings;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Workflow settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: workflow.templateId,
                      decoration:
                          const InputDecoration(labelText: 'Workflow template'),
                      items: const [
                        DropdownMenuItem(
                          value: BoardWorkflowSettings.legacyTemplateId,
                          child: Text('Legacy kanban'),
                        ),
                        DropdownMenuItem(
                          value: BoardWorkflowSettings.designatedTemplateId,
                          child: Text('Designated starter'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          workflow = workflow.copyWith(templateId: value);
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      value: workflow.allowCustomColumns,
                      title: const Text('Allow custom columns'),
                      onChanged: (value) {
                        setState(() {
                          workflow =
                              workflow.copyWith(allowCustomColumns: value);
                        });
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
                  onPressed: () async {
                    final currentTemplateId =
                        snapshot.board.workflowSettings.templateId;
                    final shouldApplyTemplate =
                        workflow.templateId != currentTemplateId &&
                            workflow.templateId ==
                                BoardWorkflowSettings.designatedTemplateId;

                    final ok = await _runGuardedAction(
                      context,
                      () async {
                        await ref
                            .read(boardControllerProvider)
                            .updateBoardWorkflowSettings(workflow);
                        if (shouldApplyTemplate) {
                          await ref
                              .read(boardControllerProvider)
                              .applyWorkflowTemplate(workflow.templateId);
                        }
                      },
                    );
                    if (ok && context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showColumnSemanticsDialog(
    BuildContext context,
    WidgetRef ref, {
    required BoardColumn column,
  }) async {
    var kind = column.kind;
    var isDoneState = column.isDoneState;
    var isBlockedState = column.isBlockedState;
    var isCancelledState = column.isCancelledState;
    var isEnabled = column.isEnabled;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Semantics: ${column.name}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<BoardColumnKind>(
                      initialValue: kind,
                      decoration: const InputDecoration(labelText: 'Kind'),
                      items: [
                        for (final entry in BoardColumnKind.values)
                          DropdownMenuItem(
                            value: entry,
                            child: Text(_workflowKindLabel(entry)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => kind = value);
                      },
                    ),
                    SwitchListTile(
                      value: isDoneState,
                      title: const Text('Done state'),
                      onChanged: (value) => setState(() => isDoneState = value),
                    ),
                    SwitchListTile(
                      value: isBlockedState,
                      title: const Text('Blocked state'),
                      onChanged: (value) =>
                          setState(() => isBlockedState = value),
                    ),
                    SwitchListTile(
                      value: isCancelledState,
                      title: const Text('Cancelled state'),
                      onChanged: (value) =>
                          setState(() => isCancelledState = value),
                    ),
                    SwitchListTile(
                      value: isEnabled,
                      title: const Text('Enabled'),
                      onChanged: (value) => setState(() => isEnabled = value),
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
                  onPressed: () async {
                    final ok = await _runGuardedAction(
                      context,
                      () => ref
                          .read(boardControllerProvider)
                          .updateColumnSemantics(
                            columnId: column.columnId,
                            kind: kind,
                            isDoneState: isDoneState,
                            isBlockedState: isBlockedState,
                            isCancelledState: isCancelledState,
                            isEnabled: isEnabled,
                          ),
                    );
                    if (ok && context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showMemberManagementSheet(
    BuildContext context,
    WidgetRef ref, {
    required BoardSnapshot snapshot,
    required String currentUserId,
  }) async {
    var inviteUserId = '';
    var inviteRole = BoardRole.member;

    final members = [...snapshot.members]..sort((a, b) {
        if (a.role == BoardRole.owner && b.role != BoardRole.owner) return -1;
        if (a.role != BoardRole.owner && b.role == BoardRole.owner) return 1;
        return a.userId.compareTo(b.userId);
      });

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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Board members',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: 'User ID',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) => inviteUserId = value,
                          ),
                        ),
                        const SizedBox(width: 8),
                        DropdownButton<BoardRole>(
                          value: inviteRole,
                          items: const [
                            DropdownMenuItem(
                                value: BoardRole.viewer, child: Text('Viewer')),
                            DropdownMenuItem(
                                value: BoardRole.member, child: Text('Member')),
                            DropdownMenuItem(
                                value: BoardRole.admin, child: Text('Admin')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => inviteRole = value);
                          },
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () async {
                            final uid = inviteUserId.trim();
                            if (uid.isEmpty) return;
                            final ok = await _runGuardedAction(
                              context,
                              () => ref
                                  .read(boardControllerProvider)
                                  .inviteMember(userId: uid, role: inviteRole),
                            );
                            if (ok && context.mounted) {
                              Navigator.of(context).pop();
                            }
                          },
                          child: const Text('Invite'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: members.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final member = members[index];
                          final pending =
                              BoardPermissions.isInvitePending(member);
                          final isOwner = member.role == BoardRole.owner;
                          final canModifyRole = !isOwner;
                          final canRemove = !isOwner;

                          return ListTile(
                            dense: true,
                            title: Text(member.userId),
                            subtitle: Text(
                              pending
                                  ? '${_roleLabel(member.role)} • Invite pending'
                                  : _roleLabel(member.role),
                            ),
                            trailing: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              children: [
                                if (isOwner)
                                  const Chip(label: Text('Owner'))
                                else
                                  DropdownButton<BoardRole>(
                                    value: member.role,
                                    items: const [
                                      DropdownMenuItem(
                                          value: BoardRole.viewer,
                                          child: Text('Viewer')),
                                      DropdownMenuItem(
                                          value: BoardRole.member,
                                          child: Text('Member')),
                                      DropdownMenuItem(
                                          value: BoardRole.admin,
                                          child: Text('Admin')),
                                    ],
                                    onChanged: !canModifyRole
                                        ? null
                                        : (value) async {
                                            if (value == null ||
                                                value == member.role) {
                                              return;
                                            }
                                            await _runGuardedAction(
                                              context,
                                              () => ref
                                                  .read(boardControllerProvider)
                                                  .updateMemberRole(
                                                    userId: member.userId,
                                                    role: value,
                                                  ),
                                            );
                                            if (context.mounted) {
                                              Navigator.of(context).pop();
                                            }
                                          },
                                  ),
                                IconButton(
                                  tooltip: member.userId == currentUserId
                                      ? 'Remove yourself'
                                      : 'Remove member',
                                  onPressed: !canRemove
                                      ? null
                                      : () async {
                                          final confirmed =
                                              await _confirmDestructiveAction(
                                            context,
                                            title:
                                                member.userId == currentUserId
                                                    ? 'Leave board?'
                                                    : 'Remove member?',
                                            message: member.userId ==
                                                    currentUserId
                                                ? 'You will lose access to this board.'
                                                : 'Remove ${member.userId} from this board?',
                                            confirmLabel: 'Remove',
                                          );
                                          if (!confirmed) return;
                                          await _runGuardedAction(
                                            context,
                                            () => ref
                                                .read(boardControllerProvider)
                                                .removeMember(member.userId),
                                          );
                                          if (context.mounted) {
                                            Navigator.of(context).pop();
                                          }
                                        },
                                  icon:
                                      const Icon(Icons.person_remove_outlined),
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
            );
          },
        );
      },
    );
  }

  Future<void> _showCreateItemDialog(
    BuildContext context,
    WidgetRef ref, {
    required bool canManageBoard,
    WorkItem? anchorItem,
  }) async {
    final targetBoardId =
        anchorItem?.boardId ?? ref.read(currentBoardIdProvider.notifier).state;
    final snapshot =
        (targetBoardId == ref.read(currentBoardIdProvider.notifier).state
                ? ref.read(boardStreamProvider).valueOrNull
                : ref.read(boardSnapshotProvider(targetBoardId)).valueOrNull) ??
            await ref.read(boardSnapshotProvider(targetBoardId).future);
    if (snapshot == null) return;
    final columns = [...snapshot.columns]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    if (columns.isEmpty) return;
    final autofillSettings = ref.read(autofillSettingsProvider).valueOrNull ??
        const AutofillSettings();
    final focusedItemId = ref.read(focusedItemIdProvider);
    final resolvedAnchor = anchorItem ??
        snapshot.items
            .where((item) => item.itemId == focusedItemId)
            .cast<WorkItem?>()
            .firstWhere((_) => true, orElse: () => null);
    List<WorkItem> parentCandidatesFor(WorkItemType type) {
      return _parentCandidatesForType(
        childType: type,
        allItems: snapshot.items,
      );
    }

    CreateItemDefaultsDraft computeDefaults(WorkItemType? selectedType) {
      return CreateItemDefaultsPolicy.resolve(
        snapshot: snapshot,
        settings: autofillSettings,
        focusedItem: resolvedAnchor,
        selectedType: selectedType,
      );
    }

    final initialDefaults = computeDefaults(null);
    WorkItemType selectedType = initialDefaults.type;
    String selectedColumnId = columns.any(
      (entry) => entry.columnId == initialDefaults.columnId,
    )
        ? initialDefaults.columnId
        : columns.first.columnId;
    String? selectedParentId = initialDefaults.parentId != null &&
            parentCandidatesFor(selectedType).any(
              (entry) => entry.itemId == initialDefaults.parentId,
            )
        ? initialDefaults.parentId
        : null;
    final titleController = TextEditingController();
    final tagsController =
        TextEditingController(text: initialDefaults.tags.join(', '));
    final estimateController = TextEditingController(
      text: initialDefaults.estimatedEffortMinutes?.toString() ?? '',
    );
    final descriptionController = TextEditingController();
    final actualEffortController = TextEditingController();
    int? selectedGoalColor;
    final autoGoalColor = chooseRandomUnusedGoalColor(
      items: snapshot.items,
      overrides: snapshot.board.validationSettings.hierarchyGoalColorOverrides,
      random: Random(),
    );
    DateTime? selectedStartAt =
        _defaultCreateStartAt(columns, selectedColumnId);
    DateTime? selectedTargetEndAt;
    DateTime? selectedDueAt;
    var recurrenceEnabled = false;
    var recurrenceCadence = WorkItemRecurrenceCadence.weekly;
    var recurrenceIntervalText = '1';
    var recurrenceMissedWindowPolicy =
        WorkItemRecurrenceMissedWindowPolicy.nextEligible;
    var showAdvanced = false;
    var columnTouched = false;
    var parentTouched = false;
    var tagsTouched = false;
    var estimateTouched = false;
    var startDateTouched = false;

    void applyDefaultsForType(
      WorkItemType type, {
      bool force = false,
    }) {
      final defaults = computeDefaults(type);
      final parentCandidates = parentCandidatesFor(type);
      if ((force || !columnTouched) &&
          columns.any((entry) => entry.columnId == defaults.columnId)) {
        selectedColumnId = defaults.columnId;
      }
      if (force || !startDateTouched) {
        selectedStartAt = _defaultCreateStartAt(columns, selectedColumnId);
      }
      if (type == WorkItemType.goal) {
        selectedParentId = null;
        parentTouched = false;
      } else if (force || !parentTouched) {
        selectedParentId = defaults.parentId != null &&
                parentCandidates.any(
                  (entry) => entry.itemId == defaults.parentId,
                )
            ? defaults.parentId
            : null;
      }
      if (selectedParentId != null &&
          !parentCandidates.any((entry) => entry.itemId == selectedParentId)) {
        selectedParentId = null;
      }
      if (force || !tagsTouched) {
        tagsController.text = defaults.tags.join(', ');
      }
      if (force || !estimateTouched) {
        estimateController.text =
            defaults.estimatedEffortMinutes?.toString() ?? '';
      }
      if (type != WorkItemType.task && type != WorkItemType.action) {
        recurrenceEnabled = false;
      }
    }

    final submitted = await showDialog<
        ({
          String title,
          WorkItemType type,
          String columnId,
          String? parentId,
          String? description,
          DateTime? startAt,
          DateTime? targetEndAt,
          DateTime? dueAt,
          List<String> tags,
          int? estimatedEffortMinutes,
          int? actualEffortMinutes,
          WorkItemRecurrence? recurrence,
          int? goalColor,
        })>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final parentCandidates = parentCandidatesFor(selectedType);
          final selectedParent = selectedParentId == null
              ? null
              : parentCandidates
                  .where((item) => item.itemId == selectedParentId)
                  .cast<WorkItem?>()
                  .firstWhere((_) => true, orElse: () => null);
          final requiresParent = _requiresParentForType(
            settings: snapshot.board.validationSettings,
            type: selectedType,
          );
          final missingRequiredParent =
              requiresParent && selectedParentId == null;
          final recurrenceSupported = selectedType == WorkItemType.task ||
              selectedType == WorkItemType.action;
          final recommendedParent = selectedParent == null
              ? true
              : _isRecommendedParentType(
                  child: selectedType,
                  parent: selectedParent.type,
                );
          final title = titleController.text.trim();
          final canSubmit = title.isNotEmpty && !missingRequiredParent;

          Widget buildDateField({
            required String label,
            required DateTime? value,
            required ValueChanged<DateTime?> onChanged,
            String? helperText,
          }) {
            return InputDecorator(
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
                helperText: helperText,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(value == null ? 'No date' : _dateOnly(value)),
                  ),
                  IconButton(
                    tooltip: 'Pick $label',
                    onPressed: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: value ?? now,
                        firstDate: DateTime(now.year - 10),
                        lastDate: DateTime(now.year + 20),
                      );
                      if (picked != null) {
                        onChanged(picked);
                      }
                    },
                    icon: const Icon(Icons.calendar_today),
                  ),
                  IconButton(
                    tooltip: 'Clear $label',
                    onPressed: value == null ? null : () => onChanged(null),
                    icon: const Icon(Icons.clear),
                  ),
                ],
              ),
            );
          }

          void submit() {
            if (!canSubmit) return;
            final recurrenceInterval =
                int.tryParse(recurrenceIntervalText.trim());
            if (recurrenceEnabled &&
                (recurrenceInterval == null || recurrenceInterval <= 0)) {
              _showActionFeedback(
                context,
                'Recurrence interval must be a positive number.',
              );
              return;
            }
            final tags = tagsController.text
                .split(',')
                .map((tag) => tag.trim())
                .where((tag) => tag.isNotEmpty)
                .toList();
            final normalizedDescription = descriptionController.text.trim();
            final recurrence = recurrenceEnabled && recurrenceSupported
                ? WorkItemRecurrence(
                    enabled: true,
                    cadence: recurrenceCadence,
                    interval: recurrenceInterval ?? 1,
                    completionGated: true,
                    missedWindowPolicy: recurrenceMissedWindowPolicy,
                    rootItemId: '',
                  )
                : null;
            Navigator.of(context).pop((
              title: title,
              type: selectedType,
              columnId: selectedColumnId,
              parentId: selectedParentId,
              description:
                  normalizedDescription.isEmpty ? null : normalizedDescription,
              startAt: selectedStartAt,
              targetEndAt: selectedTargetEndAt,
              dueAt: selectedDueAt,
              tags: tags,
              estimatedEffortMinutes:
                  int.tryParse(estimateController.text.trim()),
              actualEffortMinutes:
                  int.tryParse(actualEffortController.text.trim()),
              recurrence: recurrence,
              goalColor: selectedGoalColor,
            ));
          }

          return AlertDialog(
            title: const Text('Add item'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => submit(),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<WorkItemType>(
                    initialValue: selectedType,
                    key: ValueKey('create-type-${selectedType.name}'),
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(
                        value: WorkItemType.goal,
                        child: Text('Goal'),
                      ),
                      DropdownMenuItem(
                        value: WorkItemType.project,
                        child: Text('Project'),
                      ),
                      DropdownMenuItem(
                        value: WorkItemType.task,
                        child: Text('Task'),
                      ),
                      DropdownMenuItem(
                        value: WorkItemType.action,
                        child: Text('Action'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        selectedType = value;
                        if (selectedType != WorkItemType.goal) {
                          selectedGoalColor = null;
                        }
                        applyDefaultsForType(value);
                      });
                    },
                  ),
                  if (selectedType != WorkItemType.goal &&
                      selectedParent != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Parent: ${_workItemTypeLabel(selectedParent.type)} - ${selectedParent.title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        showAdvanced = !showAdvanced;
                      });
                    },
                    icon: Icon(
                        showAdvanced ? Icons.expand_less : Icons.expand_more),
                    label: Text(showAdvanced ? 'Hide options' : 'More options'),
                  ),
                  if (showAdvanced) ...[
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: selectedColumnId,
                      key: ValueKey('create-column-$selectedColumnId'),
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
                        setState(() {
                          selectedColumnId = value;
                          columnTouched = true;
                          if (!startDateTouched) {
                            selectedStartAt =
                                _defaultCreateStartAt(columns, value);
                          }
                        });
                      },
                    ),
                    if (selectedType != WorkItemType.goal) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        initialValue: selectedParentId,
                        key: ValueKey('create-parent-$selectedParentId'),
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText:
                              requiresParent ? 'Parent' : 'Parent (optional)',
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('None'),
                          ),
                          for (final item in parentCandidates)
                            DropdownMenuItem<String?>(
                              value: item.itemId,
                              child: Text(
                                '${_workItemTypeLabel(item.type)}: ${item.title}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            selectedParentId = value;
                            parentTouched = true;
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (snapshot.board.validationSettings.showStartDate) ...[
                      const SizedBox(height: 12),
                      buildDateField(
                        label: 'Start date',
                        value: selectedStartAt,
                        helperText:
                            snapshot.board.validationSettings.requireStartDate
                                ? 'Required by board settings'
                                : (_isInProgressColumnForCreate(
                                    columns,
                                    selectedColumnId,
                                  )
                                    ? 'Defaults to now for in-progress columns'
                                    : null),
                        onChanged: (value) {
                          setState(() {
                            selectedStartAt = value;
                            startDateTouched = true;
                          });
                        },
                      ),
                    ],
                    if (snapshot
                        .board.validationSettings.showTargetEndDate) ...[
                      const SizedBox(height: 12),
                      buildDateField(
                        label: 'Target end date',
                        value: selectedTargetEndAt,
                        helperText: snapshot
                                .board.validationSettings.requireTargetEndDate
                            ? 'Required by board settings'
                            : null,
                        onChanged: (value) {
                          setState(() {
                            selectedTargetEndAt = value;
                          });
                        },
                      ),
                    ],
                    if (snapshot.board.validationSettings.showDueDate) ...[
                      const SizedBox(height: 12),
                      buildDateField(
                        label: 'Due date',
                        value: selectedDueAt,
                        helperText:
                            snapshot.board.validationSettings.requireDueDate
                                ? 'Required by board settings'
                                : null,
                        onChanged: (value) {
                          setState(() {
                            selectedDueAt = value;
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: tagsController,
                      decoration: const InputDecoration(
                        labelText: 'Tags (comma separated)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        tagsTouched = true;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: estimateController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Estimated effort (minutes)',
                        helperText: snapshot
                                .board.validationSettings.requireEstimatedEffort
                            ? 'Required by board settings'
                            : null,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        estimateTouched = true;
                      },
                    ),
                    if (snapshot.board.validationSettings.showActualEffort) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: actualEffortController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Actual effort (minutes)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    if (recurrenceSupported) ...[
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: recurrenceEnabled,
                        title: const Text('Recurring item'),
                        subtitle: const Text(
                          'Create the next instance after this one is completed.',
                        ),
                        onChanged: (value) {
                          setState(() {
                            recurrenceEnabled = value;
                          });
                        },
                      ),
                      if (recurrenceEnabled) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<WorkItemRecurrenceCadence>(
                          initialValue: recurrenceCadence,
                          decoration: const InputDecoration(
                            labelText: 'Recurrence cadence',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: WorkItemRecurrenceCadence.daily,
                              child: Text('Daily'),
                            ),
                            DropdownMenuItem(
                              value: WorkItemRecurrenceCadence.weekly,
                              child: Text('Weekly'),
                            ),
                            DropdownMenuItem(
                              value: WorkItemRecurrenceCadence.customDays,
                              child: Text('Custom days'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              recurrenceCadence = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: recurrenceIntervalText,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: recurrenceCadence ==
                                    WorkItemRecurrenceCadence.weekly
                                ? 'Every N week(s)'
                                : 'Every N day(s)',
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            recurrenceIntervalText = value;
                          },
                        ),
                        const SizedBox(height: 12),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Generation mode',
                            border: OutlineInputBorder(),
                          ),
                          child: const Text(
                            'Completion-gated only in MVP. The next cycle is created when this item is completed.',
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<
                            WorkItemRecurrenceMissedWindowPolicy>(
                          initialValue: recurrenceMissedWindowPolicy,
                          decoration: const InputDecoration(
                            labelText: 'Late completion behavior',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: WorkItemRecurrenceMissedWindowPolicy
                                  .nextEligible,
                              child: Text('Jump to next eligible cycle'),
                            ),
                            DropdownMenuItem(
                              value: WorkItemRecurrenceMissedWindowPolicy
                                  .singleStep,
                              child: Text('Advance one cycle only'),
                            ),
                            DropdownMenuItem(
                              value: WorkItemRecurrenceMissedWindowPolicy
                                  .manualCatchUp,
                              child: Text('Skip auto-create when late'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              recurrenceMissedWindowPolicy = value;
                            });
                          },
                        ),
                      ],
                    ],
                    if (selectedType == WorkItemType.goal &&
                        canManageBoard) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int?>(
                        initialValue: selectedGoalColor,
                        key: ValueKey(
                          'create-goal-color-${selectedGoalColor ?? 'auto'}',
                        ),
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Goal color',
                          border: OutlineInputBorder(),
                        ),
                        items: _goalColorMenuItems(autoColor: autoGoalColor),
                        onChanged: (value) {
                          setState(() {
                            selectedGoalColor = value;
                          });
                        },
                      ),
                    ],
                  ],
                  if (missingRequiredParent)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'This board requires a parent for ${_workItemTypeLabel(selectedType).toLowerCase()} items. Open More options to choose one.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                    ),
                  if (selectedParent != null && !recommendedParent)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'Tip: ${_workItemTypeLabel(selectedType)} items are usually nested under a higher-level type.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.orange.shade700,
                            ),
                      ),
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
                onPressed: canSubmit ? submit : null,
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );

    if (submitted == null) return;
    final created = await _runGuardedActionWithResult(
      context,
      () => ref.read(boardControllerProvider).createItem(
            boardId: snapshot.board.boardId,
            title: submitted.title,
            type: submitted.type,
            toColumnId: submitted.columnId,
            parentId: submitted.parentId,
            description: submitted.description,
            startAt: submitted.startAt,
            targetEndAt: submitted.targetEndAt,
            dueAt: submitted.dueAt,
            tags: submitted.tags,
            estimatedEffortMinutes: submitted.estimatedEffortMinutes,
            actualEffortMinutes: submitted.actualEffortMinutes,
            recurrence: submitted.recurrence,
          ),
    );
    if (created == null) return;
    if (!canManageBoard || created.type != WorkItemType.goal) return;

    final nextColor = submitted.goalColor ?? autoGoalColor;
    final nextOverrides = Map<String, int>.from(
      snapshot.board.validationSettings.hierarchyGoalColorOverrides,
    )..[created.itemId] = nextColor;

    await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).updateBoardValidationSettings(
            snapshot.board.validationSettings.copyWith(
              hierarchyColorGroupingByGoal: true,
              hierarchyGoalColorOverrides: nextOverrides,
            ),
          ),
    );
  }

  Future<void> _showQuickCaptureDialog(
      BuildContext context, WidgetRef ref) async {
    var title = '';
    var tagsText = '';

    final submitted = await showDialog<(String, List<String>)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quick capture'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'What do you need to remember?',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => title = value,
              onSubmitted: (value) {
                final normalized = value.trim();
                if (normalized.isEmpty) return;
                Navigator.of(context).pop((normalized, const <String>[]));
              },
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: const InputDecoration(
                hintText: 'tags (optional, comma separated)',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => tagsText = value,
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
              final normalized = title.trim();
              if (normalized.isEmpty) return;
              final tags = tagsText
                  .split(',')
                  .map((tag) => tag.trim())
                  .where((tag) => tag.isNotEmpty)
                  .toList();
              Navigator.of(context).pop((normalized, tags));
            },
            child: const Text('Capture'),
          ),
        ],
      ),
    );

    if (submitted == null) return;
    final ok = await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).createInboxCapture(
            title: submitted.$1,
            tags: submitted.$2,
          ),
    );
    if (ok && context.mounted) {
      ref.read(boardWorkspaceSurfaceProvider.notifier).state =
          BoardWorkspaceSurface.inbox;
    }
  }

  Future<void> _showTriageInboxDialog(
    BuildContext context,
    WidgetRef ref, {
    required WorkItem item,
    required List<Board> boards,
  }) async {
    if (boards.isEmpty) return;
    final autofillSettings = ref.read(autofillSettingsProvider).valueOrNull ??
        const AutofillSettings();
    final boardSnapshots = <BoardSnapshot>[];
    for (final board in boards) {
      try {
        final snapshot =
            await ref.read(localBoardStoreProvider).getBoard(board.boardId);
        boardSnapshots.add(snapshot);
      } catch (_) {
        // Ignore unavailable board snapshots; fallback still deterministic.
      }
    }

    var targetBoardId = boards
            .where((board) => board.boardId == item.boardId)
            .map((board) => board.boardId)
            .cast<String?>()
            .firstWhere((_) => true, orElse: () => null) ??
        boards.first.boardId;
    targetBoardId = AutofillSuggestionPolicy.suggestBoardForInboxTriage(
          inboxItem: item,
          boardSnapshots: boardSnapshots,
          settings: autofillSettings,
          fallbackBoardId: targetBoardId,
        ) ??
        targetBoardId;
    var selectedType = item.type;
    String? selectedColumnId;
    String? selectedParentId;

    final submitted = await showDialog<(String, String, WorkItemType, String?)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Triage inbox item'),
          content: FutureBuilder<BoardSnapshot>(
            future: ref.read(localBoardStoreProvider).getBoard(targetBoardId),
            builder: (context, snapshotAsync) {
              if (!snapshotAsync.hasData) {
                return const SizedBox(
                  width: 320,
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final targetSnapshot = snapshotAsync.data!;
              final columns = [...targetSnapshot.columns]
                ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
              if (columns.isEmpty) {
                return const SizedBox(
                  width: 320,
                  child: Text('Target board has no columns.'),
                );
              }
              selectedColumnId ??= columns.first.columnId;
              if (!columns
                  .any((column) => column.columnId == selectedColumnId)) {
                selectedColumnId = columns.first.columnId;
              }
              final candidates = _parentCandidatesForType(
                childType: selectedType,
                allItems: targetSnapshot.items,
                currentItemId: item.itemId,
              );
              if (selectedParentId != null &&
                  !candidates.any(
                      (candidate) => candidate.itemId == selectedParentId)) {
                selectedParentId = null;
              }

              return SingleChildScrollView(
                child: SizedBox(
                  width: 320,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: targetBoardId,
                        decoration:
                            const InputDecoration(labelText: 'Target board'),
                        items: [
                          for (final board in boards)
                            DropdownMenuItem(
                              value: board.boardId,
                              child: Text(board.name),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null || value == targetBoardId) return;
                          setState(() {
                            targetBoardId = value;
                            selectedColumnId = null;
                            selectedParentId = null;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedColumnId,
                        decoration:
                            const InputDecoration(labelText: 'Target column'),
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
                      const SizedBox(height: 12),
                      DropdownButtonFormField<WorkItemType>(
                        initialValue: selectedType,
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: const [
                          DropdownMenuItem(
                              value: WorkItemType.goal, child: Text('Goal')),
                          DropdownMenuItem(
                              value: WorkItemType.project,
                              child: Text('Project')),
                          DropdownMenuItem(
                              value: WorkItemType.task, child: Text('Task')),
                          DropdownMenuItem(
                              value: WorkItemType.action,
                              child: Text('Action')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            selectedType = value;
                            if (!_parentCandidatesForType(
                              childType: selectedType,
                              allItems: targetSnapshot.items,
                              currentItemId: item.itemId,
                            ).any(
                              (candidate) =>
                                  candidate.itemId == selectedParentId,
                            )) {
                              selectedParentId = null;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        initialValue: selectedParentId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Parent (optional)'),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('None'),
                          ),
                          for (final candidate in candidates)
                            DropdownMenuItem<String?>(
                              value: candidate.itemId,
                              child: Text(
                                '${_workItemTypeLabel(candidate.type)}: ${candidate.title}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => selectedParentId = value),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final columnId = selectedColumnId;
                if (columnId == null) return;
                Navigator.of(context).pop(
                    (targetBoardId, columnId, selectedType, selectedParentId));
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );

    if (submitted == null) return;
    await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).triageInboxItem(
            fromBoardId: item.boardId,
            itemId: item.itemId,
            toBoardId: submitted.$1,
            toColumnId: submitted.$2,
            type: submitted.$3,
            parentId: submitted.$4,
          ),
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Pending sync operations (${pending.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: pending.isEmpty
                          ? null
                          : () async {
                              final report = await ref
                                  .read(boardControllerProvider)
                                  .syncNow(ignoreRetrySchedule: true);
                              if (!context.mounted) return;
                              Navigator.of(context).pop();
                              _showActionFeedback(
                                context,
                                'Sync complete: ${report.processed} processed, ${report.failed} failed',
                                severity: WorkspaceFeedbackSeverity.success,
                              );
                            },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry now'),
                    ),
                  ],
                ),
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
                          title: Text(
                              '${op.type.name.toUpperCase()} ${op.entity}'),
                          subtitle: Text([
                            op.entityId,
                            if (op.attemptCount > 0)
                              'Attempts: ${op.attemptCount}',
                            if (op.nextAttemptAt != null)
                              'Retry in ${_formatRetryTime(op.nextAttemptAt!)}',
                            if (op.lastError?.isNotEmpty == true)
                              'Last error: ${op.lastError}',
                          ].join('\n')),
                          isThreeLine: true,
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

  String _boardScopeLabel(List<Board> boards, Set<String> selectedBoardIds) {
    if (boards.isEmpty) return 'No boards';
    if (selectedBoardIds.isEmpty || selectedBoardIds.length >= boards.length) {
      return 'All boards';
    }
    if (selectedBoardIds.length == 1) {
      final boardId = selectedBoardIds.first;
      final board = boards
          .where((entry) => entry.boardId == boardId)
          .cast<Board?>()
          .firstWhere((_) => true, orElse: () => null);
      return board?.name ?? '1 board';
    }
    return '${selectedBoardIds.length} boards';
  }

  Future<void> _showBoardSelectionSheet(
    BuildContext context,
    WidgetRef ref, {
    required List<Board> boards,
    required Set<String> selectedBoardIds,
    required String currentBoardId,
  }) async {
    if (boards.isEmpty) return;

    final allBoardIds = {for (final board in boards) board.boardId};
    var working = selectedBoardIds.isEmpty
        ? {...allBoardIds}
        : {...selectedBoardIds.where(allBoardIds.contains)};
    if (working.isEmpty) {
      working = {...allBoardIds};
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final allSelected = working.length == allBoardIds.length;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Board selection',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('All boards'),
                    value: allSelected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          working = {...allBoardIds};
                        } else {
                          working = {currentBoardId};
                        }
                      });
                    },
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final board in boards)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            onTap: () {
                              setState(() {
                                working.add(board.boardId);
                              });
                              ref
                                  .read(boardControllerProvider)
                                  .switchBoard(board.boardId);
                            },
                            leading: Checkbox(
                              value: working.contains(board.boardId),
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    working.add(board.boardId);
                                  } else if (working.length > 1) {
                                    working.remove(board.boardId);
                                  }
                                });
                              },
                            ),
                            title: Text(board.name),
                            trailing: board.boardId == currentBoardId
                                ? const Chip(label: Text('Active'))
                                : null,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () {
                        final normalized = working.length >= allBoardIds.length
                            ? <String>{}
                            : working;
                        ref
                            .read(workspaceSelectedBoardIdsProvider.notifier)
                            .state = normalized;

                        final allowedIds =
                            normalized.isEmpty ? allBoardIds : normalized;
                        if (!allowedIds
                            .contains(ref.read(currentBoardIdProvider))) {
                          final fallback = boards
                              .where(
                                  (entry) => allowedIds.contains(entry.boardId))
                              .map((entry) => entry.boardId)
                              .cast<String?>()
                              .firstWhere((_) => true, orElse: () => null);
                          if (fallback != null) {
                            ref
                                .read(boardControllerProvider)
                                .switchBoard(fallback);
                          }
                        }
                        Navigator.of(context).pop();
                      },
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showSmartChildCreateDialog(
    BuildContext context,
    WidgetRef ref, {
    required WorkItem parent,
    required bool canManageBoard,
  }) async {
    await _showCreateItemDialog(
      context,
      ref,
      canManageBoard: canManageBoard,
      anchorItem: parent,
    );
  }

  String _dateOnly(DateTime date) => date.toIso8601String().split('T').first;
  String _minutesLabel(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (remainingMinutes == 0) return '${hours}h';
    return '${hours}h ${remainingMinutes}m';
  }

  String _hierarchyPath({
    required WorkItem item,
    required List<WorkItem> allItems,
  }) {
    final byId = {for (final entry in allItems) entry.itemId: entry};
    final segments = <String>[item.title];
    var cursor = item;
    final visited = <String>{item.itemId};
    while (cursor.parentId != null) {
      final parent = byId[cursor.parentId!];
      if (parent == null) break;
      if (!visited.add(parent.itemId)) break;
      segments.insert(0, parent.title);
      cursor = parent;
    }
    return segments.join(' > ');
  }

  String _activityLabel(WorkItemActivityType type) {
    return switch (type) {
      WorkItemActivityType.created => 'Created',
      WorkItemActivityType.updated => 'Updated',
      WorkItemActivityType.moved => 'Moved',
      WorkItemActivityType.reparented => 'Re-parented',
      WorkItemActivityType.archived => 'Archived',
      WorkItemActivityType.unarchived => 'Unarchived',
      WorkItemActivityType.completed => 'Completed',
      WorkItemActivityType.reopened => 'Reopened',
    };
  }

  String _typeLabel(WorkItemType type) {
    return switch (type) {
      WorkItemType.goal => 'Goal',
      WorkItemType.project => 'Project',
      WorkItemType.task => 'Task',
      WorkItemType.action => 'Action',
    };
  }

  String _formatDetailsDate(BuildContext context, DateTime date) {
    return MaterialLocalizations.of(context).formatMediumDate(date);
  }

  String _formatDetailsDateTime(BuildContext context, DateTime date) {
    final localizations = MaterialLocalizations.of(context);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(date),
      alwaysUse24HourFormat:
          MediaQuery.maybeOf(context)?.alwaysUse24HourFormat ?? false,
    );
    return '${localizations.formatMediumDate(date)} • $time';
  }

  String? _relativeDateHint(DateTime date, {bool overdue = false}) {
    final today = DateUtils.dateOnly(DateTime.now());
    final target = DateUtils.dateOnly(date);
    final diffDays = target.difference(today).inDays;
    if (overdue && diffDays < 0) return 'Overdue';
    if (diffDays == 0) return 'Today';
    if (diffDays == 1) return 'Tomorrow';
    if (diffDays == -1) return 'Yesterday';
    if (diffDays > 1 && diffDays <= 7) return 'In $diffDays days';
    if (diffDays < -1 && diffDays >= -7) return '${diffDays.abs()} days ago';
    return null;
  }

  bool _isItemOverdue(WorkItem item) {
    final dueAt = item.dueAt;
    if (dueAt == null || item.completedAt != null) return false;
    return DateUtils.dateOnly(dueAt)
        .isBefore(DateUtils.dateOnly(DateTime.now()));
  }

  String _recurrenceSummary(WorkItemRecurrence recurrence) {
    final cadence = switch (recurrence.cadence) {
      WorkItemRecurrenceCadence.daily => 'Daily',
      WorkItemRecurrenceCadence.weekly => 'Weekly',
      WorkItemRecurrenceCadence.customDays => 'Custom days',
    };
    return '$cadence every ${recurrence.interval} • completion-gated • ${_recurrenceMissedWindowLabel(recurrence.missedWindowPolicy)}';
  }

  IconData _activityIcon(WorkItemActivityType type) {
    return switch (type) {
      WorkItemActivityType.created => Icons.add_circle_outline,
      WorkItemActivityType.updated => Icons.edit_outlined,
      WorkItemActivityType.moved => Icons.swap_horiz_outlined,
      WorkItemActivityType.reparented => Icons.account_tree_outlined,
      WorkItemActivityType.archived => Icons.archive_outlined,
      WorkItemActivityType.unarchived => Icons.unarchive_outlined,
      WorkItemActivityType.completed => Icons.task_alt_outlined,
      WorkItemActivityType.reopened => Icons.restart_alt_outlined,
    };
  }

  Widget _buildDetailsSectionCard(
    BuildContext context, {
    required String title,
    required Widget child,
    String? subtitle,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsFactTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    String? hint,
    bool emphasized = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = emphasized
        ? colorScheme.errorContainer.withValues(alpha: 0.65)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.45);
    final foregroundColor =
        emphasized ? colorScheme.onErrorContainer : colorScheme.onSurface;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 132, maxWidth: 180),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: foregroundColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: emphasized
                              ? foregroundColor
                              : colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: foregroundColor,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: emphasized
                          ? foregroundColor.withValues(alpha: 0.85)
                          : colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsFieldRow(
    BuildContext context, {
    required String label,
    required String value,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityRow(
    BuildContext context, {
    required WorkItemActivityEvent event,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color:
                  colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(15),
            ),
            alignment: Alignment.center,
            child: Icon(
              _activityIcon(event.type),
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _activityLabel(event.type),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDetailsDateTime(context, event.createdAt.toLocal()),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showItemDetailsSheet(
    BuildContext context,
    WidgetRef ref, {
    required WorkItem item,
    required List<WorkItem> allItems,
    required List<BoardColumn> columns,
    required BoardValidationSettings settings,
  }) async {
    await showBoardItemDetailsSheet(
      context,
      ref,
      item: item,
      allItems: allItems,
      columns: columns,
      settings: settings,
      onEdit: (currentItem, liveItems, liveSettings) => _showEditItemSheet(
        context,
        ref,
        item: currentItem,
        allItems: liveItems,
        settings: liveSettings,
      ),
      onMoveToColumn: (currentItem, toColumnId) => _moveItemWithUndo(
        context,
        ref,
        item: currentItem,
        toColumnId: toColumnId,
      ),
    );
  }

  void _focusItem(
    WidgetRef ref, {
    required WorkItem item,
  }) {
    final planningView = ref.read(boardPlanningViewProvider);
    final selectedBoardIds = ref.read(workspaceSelectedBoardIdsProvider);
    final isMultiBoardWorkspaceScope =
        selectedBoardIds.isEmpty || selectedBoardIds.length > 1;
    final shouldSwitchActiveBoard =
        ref.read(currentBoardIdProvider) != item.boardId &&
            !(planningView == BoardPlanningView.hierarchy &&
                isMultiBoardWorkspaceScope);

    if (shouldSwitchActiveBoard) {
      ref.read(boardControllerProvider).switchBoard(item.boardId);
    }
    _setFocusedItemId(
      ref,
      item.itemId,
      hierarchyItemKey: _hierarchyNodeKeyForItem(item),
    );
  }

  void _setFocusedItemId(
    WidgetRef ref,
    String? itemId, {
    String? hierarchyItemKey,
  }) {
    ref.read(focusedItemIdProvider.notifier).state = itemId;
    final planningView = ref.read(boardPlanningViewProvider);
    ref.read(selectedHierarchyItemIdProvider.notifier).state =
        planningView == BoardPlanningView.hierarchy ? hierarchyItemKey : null;
  }

  Future<void> _showEditItemSheet(
    BuildContext context,
    WidgetRef ref, {
    required WorkItem item,
    required List<WorkItem> allItems,
    required BoardValidationSettings settings,
  }) async {
    var title = item.title;
    var description = item.description ?? '';
    DateTime? selectedStartAt = item.startAt;
    DateTime? selectedTargetEndAt = item.targetEndAt;
    DateTime? selectedDueAt = item.dueAt;
    var estimatedEffortText = item.estimatedEffortMinutes?.toString() ?? '';
    var actualEffortText = item.actualEffortMinutes?.toString() ?? '';
    var tagsText = item.tags.join(', ');
    String? selectedParentId = item.parentId;
    var recurrenceEnabled = item.recurrence?.enabled == true;
    var recurrenceCadence =
        item.recurrence?.cadence ?? WorkItemRecurrenceCadence.weekly;
    var recurrenceIntervalText = (item.recurrence?.interval ?? 1).toString();
    var recurrenceMissedWindowPolicy = item.recurrence?.missedWindowPolicy ??
        WorkItemRecurrenceMissedWindowPolicy.nextEligible;
    final recurrenceSupported =
        item.type == WorkItemType.task || item.type == WorkItemType.action;
    final permissionProfile = ref.read(boardPermissionProfileProvider);
    final canManageBoard =
        permissionProfile?.has(BoardCapability.manageBoard) ?? false;
    int? selectedGoalColor = item.type == WorkItemType.goal
        ? settings.hierarchyGoalColorOverrides[item.itemId]
        : null;
    final autoGoalColor = chooseRandomUnusedGoalColor(
      items: allItems.where((entry) => entry.itemId != item.itemId),
      overrides: settings.hierarchyGoalColorOverrides,
      random: Random(),
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final parentCandidates = _parentCandidatesForType(
              childType: item.type,
              allItems: allItems,
              currentItemId: item.itemId,
              preserveParentId: item.parentId,
            );
            Widget buildDateField({
              required String label,
              required DateTime? value,
              required ValueChanged<DateTime?> onChanged,
            }) {
              return InputDecorator(
                decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                  helperText: switch (label) {
                    'Start date' when settings.requireStartDate =>
                      'Required by board settings',
                    'Target end date' when settings.requireTargetEndDate =>
                      'Required by board settings',
                    'Due date' when settings.requireDueDate =>
                      'Required by board settings',
                    _ => null,
                  },
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(value == null ? 'No date' : _dateOnly(value)),
                    ),
                    IconButton(
                      tooltip: 'Pick $label',
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: value ?? now,
                          firstDate: DateTime(now.year - 10),
                          lastDate: DateTime(now.year + 20),
                        );
                        if (picked != null) {
                          onChanged(picked);
                        }
                      },
                      icon: const Icon(Icons.calendar_today),
                    ),
                    IconButton(
                      tooltip: 'Clear $label',
                      onPressed: value == null ? null : () => onChanged(null),
                      icon: const Icon(Icons.clear),
                    ),
                  ],
                ),
              );
            }

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
                      Text('Edit item',
                          style: Theme.of(context).textTheme.titleMedium),
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
                      if (settings.showStartDate)
                        buildDateField(
                          label: 'Start date',
                          value: selectedStartAt,
                          onChanged: (value) =>
                              setState(() => selectedStartAt = value),
                        ),
                      if (settings.showStartDate) const SizedBox(height: 12),
                      if (settings.showTargetEndDate)
                        buildDateField(
                          label: 'Target end date',
                          value: selectedTargetEndAt,
                          onChanged: (value) =>
                              setState(() => selectedTargetEndAt = value),
                        ),
                      if (settings.showTargetEndDate)
                        const SizedBox(height: 12),
                      if (settings.showDueDate)
                        buildDateField(
                          label: 'Due date',
                          value: selectedDueAt,
                          onChanged: (value) =>
                              setState(() => selectedDueAt = value),
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
                          const DropdownMenuItem<String?>(
                              value: null, child: Text('None')),
                          for (final candidate in parentCandidates)
                            DropdownMenuItem<String?>(
                              value: candidate.itemId,
                              child: Text(
                                _parentCandidateLabel(
                                  child: item,
                                  candidate: candidate,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => selectedParentId = value),
                      ),
                      if (item.type == WorkItemType.goal && canManageBoard) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int?>(
                          initialValue: selectedGoalColor,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Goal color',
                            border: OutlineInputBorder(),
                          ),
                          items: _goalColorMenuItems(autoColor: autoGoalColor),
                          onChanged: (value) {
                            setState(() => selectedGoalColor = value);
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: tagsText,
                        decoration: const InputDecoration(
                          labelText: 'Tags (comma separated)',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => tagsText = value,
                      ),
                      if (settings.showEstimatedEffort) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: estimatedEffortText,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Estimated effort (minutes)',
                            helperText: settings.requireEstimatedEffort
                                ? 'Required by board settings'
                                : null,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (value) => estimatedEffortText = value,
                        ),
                      ],
                      if (settings.showActualEffort) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: actualEffortText,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Actual effort (minutes)',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) => actualEffortText = value,
                        ),
                      ],
                      if (recurrenceSupported) ...[
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: recurrenceEnabled,
                          title: const Text('Recurring item'),
                          subtitle: const Text(
                            'Create next instance after completion.',
                          ),
                          onChanged: (value) {
                            setState(() => recurrenceEnabled = value);
                          },
                        ),
                        if (recurrenceEnabled) ...[
                          const SizedBox(height: 8),
                          DropdownButtonFormField<WorkItemRecurrenceCadence>(
                            initialValue: recurrenceCadence,
                            decoration: const InputDecoration(
                              labelText: 'Recurrence cadence',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: WorkItemRecurrenceCadence.daily,
                                child: Text('Daily'),
                              ),
                              DropdownMenuItem(
                                value: WorkItemRecurrenceCadence.weekly,
                                child: Text('Weekly'),
                              ),
                              DropdownMenuItem(
                                value: WorkItemRecurrenceCadence.customDays,
                                child: Text('Custom days'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => recurrenceCadence = value);
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            initialValue: recurrenceIntervalText,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: recurrenceCadence ==
                                      WorkItemRecurrenceCadence.weekly
                                  ? 'Every N week(s)'
                                  : 'Every N day(s)',
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (value) =>
                                recurrenceIntervalText = value,
                          ),
                          const SizedBox(height: 12),
                          InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Generation mode',
                              border: OutlineInputBorder(),
                            ),
                            child: const Text(
                              'Completion-gated only in MVP. The next cycle is created when this item is completed.',
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<
                              WorkItemRecurrenceMissedWindowPolicy>(
                            initialValue: recurrenceMissedWindowPolicy,
                            decoration: const InputDecoration(
                              labelText: 'Late completion behavior',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: WorkItemRecurrenceMissedWindowPolicy
                                    .nextEligible,
                                child: Text('Jump to next eligible cycle'),
                              ),
                              DropdownMenuItem(
                                value: WorkItemRecurrenceMissedWindowPolicy
                                    .singleStep,
                                child: Text('Advance one cycle only'),
                              ),
                              DropdownMenuItem(
                                value: WorkItemRecurrenceMissedWindowPolicy
                                    .manualCatchUp,
                                child: Text('Skip auto-create when late'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setState(
                                () => recurrenceMissedWindowPolicy = value,
                              );
                            },
                          ),
                        ],
                      ],
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
                              final startAt = selectedStartAt;
                              final clearStartAt = selectedStartAt == null;
                              final targetEndAt = selectedTargetEndAt;
                              final clearTargetEndAt =
                                  selectedTargetEndAt == null;
                              final dueAt = selectedDueAt;
                              final clearDueAt = selectedDueAt == null;
                              final estimatedEffortMinutes =
                                  int.tryParse(estimatedEffortText.trim());
                              final actualEffortMinutes =
                                  int.tryParse(actualEffortText.trim());
                              final clearEstimatedEffort =
                                  estimatedEffortText.trim().isEmpty;
                              final clearActualEffort =
                                  actualEffortText.trim().isEmpty;
                              final recurrenceInterval = int.tryParse(
                                recurrenceIntervalText.trim(),
                              );
                              if (recurrenceEnabled &&
                                  (recurrenceInterval == null ||
                                      recurrenceInterval <= 0)) {
                                _showActionFeedback(
                                  context,
                                  'Recurrence interval must be a positive number.',
                                );
                                return;
                              }
                              final recurrence = recurrenceEnabled
                                  ? WorkItemRecurrence(
                                      enabled: true,
                                      cadence: recurrenceCadence,
                                      interval: recurrenceInterval ?? 1,
                                      completionGated: true,
                                      missedWindowPolicy:
                                          recurrenceMissedWindowPolicy,
                                      rootItemId: item.recurrence?.rootItemId ??
                                          item.itemId,
                                      sequence: item.recurrence?.sequence ?? 0,
                                    )
                                  : null;

                              final tags = tagsText
                                  .split(',')
                                  .map((t) => t.trim())
                                  .where((t) => t.isNotEmpty)
                                  .toList();

                              final ok = await _runGuardedAction(
                                context,
                                () => ref
                                    .read(boardControllerProvider)
                                    .updateItem(
                                      boardId: item.boardId,
                                      itemId: item.itemId,
                                      title: normalizedTitle,
                                      description: normalizedDescription.isEmpty
                                          ? null
                                          : normalizedDescription,
                                      clearDescription:
                                          normalizedDescription.isEmpty,
                                      parentId: selectedParentId,
                                      clearParent: selectedParentId == null,
                                      startAt: startAt,
                                      clearStartAt: clearStartAt,
                                      targetEndAt: targetEndAt,
                                      clearTargetEndAt: clearTargetEndAt,
                                      dueAt: dueAt,
                                      clearDueAt: clearDueAt,
                                      estimatedEffortMinutes:
                                          estimatedEffortMinutes,
                                      clearEstimatedEffort:
                                          clearEstimatedEffort,
                                      actualEffortMinutes: actualEffortMinutes,
                                      clearActualEffort: clearActualEffort,
                                      recurrence: recurrence,
                                      clearRecurrence: !recurrenceEnabled,
                                      tags: tags,
                                    ),
                              );
                              if (ok && context.mounted) {
                                if (item.type == WorkItemType.goal &&
                                    canManageBoard) {
                                  final nextOverrides = Map<String, int>.from(
                                    settings.hierarchyGoalColorOverrides,
                                  );
                                  if (selectedGoalColor == null) {
                                    nextOverrides.remove(item.itemId);
                                  } else {
                                    nextOverrides[item.itemId] =
                                        selectedGoalColor!;
                                  }
                                  await _runGuardedAction(
                                    context,
                                    () => ref
                                        .read(boardControllerProvider)
                                        .updateBoardValidationSettings(
                                          settings.copyWith(
                                            hierarchyColorGroupingByGoal: true,
                                            hierarchyGoalColorOverrides:
                                                nextOverrides,
                                          ),
                                          boardId: item.boardId,
                                        ),
                                  );
                                }
                                Navigator.of(context).pop();
                              }
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

  void _toggleItemSelection(WidgetRef ref, String itemId) {
    final current = ref.read(selectedBoardItemIdsProvider);
    final next = <String>{...current};
    if (!next.add(itemId)) {
      next.remove(itemId);
    }
    ref.read(selectedBoardItemIdsProvider.notifier).state = next;
  }

  List<WorkItem> _sharedVisibleItems({
    required List<WorkItem> items,
    required Set<WorkItemType> filters,
    required BoardItemStateFilter stateFilter,
    required bool focusModeEnabled,
    required Set<String>? focusRelatedItemIds,
    required String textQuery,
    required String tagFilter,
    required Map<String, BoardColumn> columnsById,
    required bool showOverdueOnly,
    required bool showDueSoonOnly,
    required bool showArchivedOnly,
  }) {
    final visible = items
        .where(
          (item) => _isVisibleInCurrentModes(
            item: item,
            filters: filters,
            stateFilter: stateFilter,
            focusModeEnabled: focusModeEnabled,
            focusRelatedItemIds: focusRelatedItemIds,
            textQuery: textQuery,
            tagFilter: tagFilter,
            columnsById: columnsById,
            showOverdueOnly: showOverdueOnly,
            showDueSoonOnly: showDueSoonOnly,
            showArchivedOnly: showArchivedOnly,
          ),
        )
        .toList();

    visible.sort((a, b) {
      final byType = _typeRank(a.type).compareTo(_typeRank(b.type));
      if (byType != 0) return byType;

      final byDone = (a.completedAt != null ? 1 : 0)
          .compareTo(b.completedAt != null ? 1 : 0);
      if (byDone != 0) return byDone;

      final byUpdated = b.updatedAt.compareTo(a.updatedAt);
      if (byUpdated != 0) return byUpdated;

      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return visible;
  }

  Widget _buildInboxView({
    required BuildContext context,
    required WidgetRef ref,
    required List<WorkItem> allItems,
    required List<BoardColumn> columns,
    required List<Board> boards,
    required bool canModifyItems,
    required bool canManageBoard,
    required Set<String> selectedItemIds,
    required String? focusedItemId,
    required BoardCardDensity density,
    required BoardValidationSettings settings,
  }) {
    final compactDensity = density == BoardCardDensity.compact;
    final inboxItems = allItems.where((item) => item.isInbox).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (inboxItems.isEmpty) {
      return const Center(
        child: Text('Inbox is empty. Use Quick capture to add ideas fast.'),
      );
    }

    return ListView(
      padding: EdgeInsets.all(compactDensity ? 2 : 8),
      children: [
        for (final item in inboxItems)
          Padding(
            padding: EdgeInsets.only(bottom: compactDensity ? 1 : 8),
            child: BoardItemTile(
              item: item,
              columns: columns,
              allItems: allItems,
              focused: focusedItemId == item.itemId,
              selected: selectedItemIds.contains(item.itemId),
              childCount: allItems
                  .where((entry) => entry.parentId == item.itemId)
                  .length,
              onSelect: () {
                _focusItem(
                  ref,
                  item: item,
                );
              },
              onAddChildAction: () {
                _showSmartChildCreateDialog(
                  context,
                  ref,
                  parent: item,
                  canManageBoard: canManageBoard,
                );
              },
              onEdit: () {
                _showEditItemSheet(
                  context,
                  ref,
                  item: item,
                  allItems: allItems,
                  settings: settings,
                );
              },
              onViewDetails: () {
                _showItemDetailsSheet(
                  context,
                  ref,
                  item: item,
                  allItems: allItems,
                  columns: columns,
                  settings: settings,
                );
              },
              onToggleArchive: () {
                _toggleArchiveWithUndo(context, ref, item: item);
              },
              density: density,
              parentPathMode: settings.hierarchyParentPathMode,
              onMoveToColumn: (toColumnId) => _moveItemWithUndo(
                context,
                ref,
                item: item,
                toColumnId: toColumnId,
              ),
              onToggleSelected: () => _toggleItemSelection(ref, item.itemId),
              onReparent: canModifyItems
                  ? () => _showReparentDialog(
                        context,
                        ref,
                        item: item,
                        allItems: allItems,
                      )
                  : null,
              onTriage: canModifyItems
                  ? () => _showTriageInboxDialog(
                        context,
                        ref,
                        item: item,
                        boards: boards,
                      )
                  : null,
              onDelete: canModifyItems
                  ? () => _deleteItemWithUndo(
                        context,
                        ref,
                        item: item,
                        allItems: allItems,
                      )
                  : null,
              onJumpToParent: item.parentId == null
                  ? null
                  : () {
                      ref.read(boardVisibilityFilterProvider.notifier).state =
                          <WorkItemType>{};
                      _setFocusedItemId(
                        ref,
                        item.parentId,
                        hierarchyItemKey: item.parentId == null
                            ? null
                            : _hierarchyNodeKey(
                                boardId: item.boardId,
                                itemId: item.parentId!,
                              ),
                      );
                      ref.read(focusModeEnabledProvider.notifier).state = true;
                    },
              canModifyItems: canModifyItems,
            ),
          ),
      ],
    );
  }

  Widget _buildWorkspaceBoardHeading(
    BuildContext context,
    WidgetRef ref, {
    required _WorkspaceBoardViewData boardView,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: boardView.isActiveBoard
                ? null
                : () {
                    ref.read(boardControllerProvider).switchBoard(
                          boardView.board.boardId,
                        );
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Text(
                boardView.board.name,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (boardView.isActiveBoard)
            const Chip(
              label: Text('Active'),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _buildMultiBoardInboxView({
    required BuildContext context,
    required WidgetRef ref,
    required List<_WorkspaceBoardViewData> boardViews,
    required List<Board> boards,
    required String? focusedItemId,
    required Set<String> selectedItemIds,
    required BoardCardDensity density,
    required bool canModifyItems,
    required bool canManageBoard,
    required Map<String, BoardPermissionProfile> permissionProfilesByBoardId,
  }) {
    final compactDensity = density == BoardCardDensity.compact;
    final sections = <Widget>[];

    for (final boardView in boardViews) {
      final snapshot = boardView.snapshot;
      final boardItems = snapshot.items;
      final boardColumns = [...snapshot.columns]
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      final inboxItems = boardItems.where((item) => item.isInbox).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (inboxItems.isEmpty) {
        continue;
      }
      final boardPermissionProfile =
          permissionProfilesByBoardId[boardView.board.boardId];
      final boardCanModifyItems =
          boardPermissionProfile?.has(BoardCapability.modifyItems) ??
              canModifyItems;
      final boardCanManage =
          boardPermissionProfile?.has(BoardCapability.manageBoard) ??
              canManageBoard;
      sections.add(_buildWorkspaceBoardHeading(
        context,
        ref,
        boardView: boardView,
      ));
      sections.addAll([
        for (final item in inboxItems)
          Padding(
            padding: EdgeInsets.only(bottom: compactDensity ? 1 : 8),
            child: BoardItemTile(
              item: item,
              columns: boardColumns,
              allItems: boardItems,
              focused: focusedItemId == item.itemId,
              selected: selectedItemIds.contains(item.itemId),
              childCount: boardItems
                  .where((entry) => entry.parentId == item.itemId)
                  .length,
              onSelect: () => _focusItem(ref, item: item),
              onAddChildAction: () {
                _showSmartChildCreateDialog(
                  context,
                  ref,
                  parent: item,
                  canManageBoard: boardCanManage,
                );
              },
              onEdit: () {
                _showEditItemSheet(
                  context,
                  ref,
                  item: item,
                  allItems: boardItems,
                  settings: snapshot.board.validationSettings,
                );
              },
              onViewDetails: () {
                _showItemDetailsSheet(
                  context,
                  ref,
                  item: item,
                  allItems: boardItems,
                  columns: boardColumns,
                  settings: snapshot.board.validationSettings,
                );
              },
              onToggleArchive: () {
                _toggleArchiveWithUndo(context, ref, item: item);
              },
              density: density,
              parentPathMode:
                  snapshot.board.validationSettings.hierarchyParentPathMode,
              onMoveToColumn: (toColumnId) => _moveItemWithUndo(
                context,
                ref,
                item: item,
                toColumnId: toColumnId,
              ),
              onToggleSelected: () => _toggleItemSelection(ref, item.itemId),
              onReparent: boardCanModifyItems
                  ? () => _showReparentDialog(
                        context,
                        ref,
                        item: item,
                        allItems: boardItems,
                      )
                  : null,
              onTriage: boardCanModifyItems
                  ? () => _showTriageInboxDialog(
                        context,
                        ref,
                        item: item,
                        boards: boards,
                      )
                  : null,
              onDelete: boardCanModifyItems
                  ? () => _deleteItemWithUndo(
                        context,
                        ref,
                        item: item,
                        allItems: boardItems,
                      )
                  : null,
              onJumpToParent: item.parentId == null
                  ? null
                  : () {
                      ref.read(boardVisibilityFilterProvider.notifier).state =
                          <WorkItemType>{};
                      _setFocusedItemId(
                        ref,
                        item.parentId,
                        hierarchyItemKey: item.parentId == null
                            ? null
                            : _hierarchyNodeKey(
                                boardId: item.boardId,
                                itemId: item.parentId!,
                              ),
                      );
                      ref.read(focusModeEnabledProvider.notifier).state = true;
                    },
              canModifyItems: boardCanModifyItems,
            ),
          ),
      ]);
    }

    if (sections.isEmpty) {
      return const Center(
        child: Text('Inbox is empty. Use Quick capture to add ideas fast.'),
      );
    }

    return ListView(
      padding: EdgeInsets.all(compactDensity ? 2 : 8),
      children: sections,
    );
  }

  Widget _buildMultiBoardKanbanView({
    required BuildContext context,
    required WidgetRef ref,
    required List<_WorkspaceBoardViewData> boardViews,
    required Set<WorkItemType> filters,
    required BoardItemStateFilter stateFilter,
    required bool focusModeEnabled,
    required Set<String>? focusRelatedItemIds,
    required String textQuery,
    required String tagFilter,
    required bool showOverdueOnly,
    required bool showDueSoonOnly,
    required bool showArchivedOnly,
    required String? focusedItemId,
    required bool canModifyItems,
    required bool canManageBoard,
    required Set<String> selectedItemIds,
    required BoardCardDensity density,
    required double columnWidth,
    required Map<String, BoardPermissionProfile> permissionProfilesByBoardId,
  }) {
    final compactDensity = density == BoardCardDensity.compact;
    final activeBoardId = boardViews
        .where((view) => view.isActiveBoard)
        .map((view) => view.board.boardId)
        .cast<String?>()
        .firstWhere((_) => true, orElse: () => null);
    final visibleItemsByBoardId = <String, Map<String, List<WorkItem>>>{};
    final boardColumnsById = <String, Map<String, BoardColumn>>{};
    final boardItemsById = <String, Map<String, WorkItem>>{};
    final boardGoalColors = <String, Map<String, int>>{};
    final laneColumnsByKey = <String, Map<String, BoardColumn>>{};
    final laneOrderByKey = <String, int>{};

    for (final boardView in boardViews) {
      final snapshot = boardView.snapshot;
      final boardId = boardView.board.boardId;
      final boardColumns = [...snapshot.columns]
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      final columnsById = {
        for (final column in boardColumns) column.columnId: column,
      };
      final itemsById = {
        for (final item in snapshot.items) item.itemId: item,
      };
      final hierarchyColorEnabled =
          snapshot.board.validationSettings.hierarchyColorGroupingByGoal;
      final goalColors = hierarchyColorEnabled
          ? resolveGoalColors(
              items: snapshot.items,
              overrides:
                  snapshot.board.validationSettings.hierarchyGoalColorOverrides,
            )
          : const <String, int>{};

      boardColumnsById[boardId] = columnsById;
      boardItemsById[boardId] = itemsById;
      boardGoalColors[boardId] = goalColors;
      visibleItemsByBoardId[boardId] = {
        for (final column in boardColumns)
          column.columnId: _sortedVisibleItems(
            items: snapshot.items,
            columnId: column.columnId,
            filters: filters,
            stateFilter: stateFilter,
            focusModeEnabled: focusModeEnabled,
            focusRelatedItemIds: focusRelatedItemIds,
            textQuery: textQuery,
            tagFilter: tagFilter,
            columnsById: columnsById,
            showOverdueOnly: showOverdueOnly,
            showDueSoonOnly: showDueSoonOnly,
            showArchivedOnly: showArchivedOnly,
          ),
      };

      for (final column in boardColumns) {
        final laneKey = _multiBoardKanbanLaneKey(column);
        laneColumnsByKey.putIfAbsent(
            laneKey, () => <String, BoardColumn>{})[boardId] = column;
        final nextOrder = column.orderIndex;
        final currentOrder = laneOrderByKey[laneKey];
        if (currentOrder == null || nextOrder < currentOrder) {
          laneOrderByKey[laneKey] = nextOrder;
        }
      }
    }

    BoardColumn laneDisplayColumn(Map<String, BoardColumn> columnsByBoardId) {
      if (activeBoardId != null) {
        final active = columnsByBoardId[activeBoardId];
        if (active != null) return active;
      }
      for (final boardView in boardViews) {
        final candidate = columnsByBoardId[boardView.board.boardId];
        if (candidate != null) return candidate;
      }
      return columnsByBoardId.values.first;
    }

    final lanes = laneColumnsByKey.entries
        .map(
          (entry) => _MergedKanbanLaneData(
            key: entry.key,
            displayColumn: laneDisplayColumn(entry.value),
            columnsByBoardId: entry.value,
            orderIndex: laneOrderByKey[entry.key] ?? 0,
          ),
        )
        .toList()
      ..sort((a, b) {
        final byOrder = a.orderIndex.compareTo(b.orderIndex);
        if (byOrder != 0) return byOrder;
        return a.displayColumn.name
            .toLowerCase()
            .compareTo(b.displayColumn.name.toLowerCase());
      });

    final children = <Widget>[];

    for (final lane in lanes) {
      final totalVisibleItems = lane.columnsByBoardId.entries.fold<int>(
        0,
        (sum, entry) =>
            sum +
            (visibleItemsByBoardId[entry.key]?[entry.value.columnId]?.length ??
                0),
      );
      final hasMultipleBoards = lane.columnsByBoardId.length > 1;
      final laneChildren = <Widget>[];

      for (final boardView in boardViews) {
        final boardId = boardView.board.boardId;
        final boardColumn = lane.columnsByBoardId[boardId];
        if (boardColumn == null) continue;

        final snapshot = boardView.snapshot;
        final tileItems = visibleItemsByBoardId[boardId]
                ?[boardColumn.columnId] ??
            const <WorkItem>[];
        final boardPermissionProfile =
            permissionProfilesByBoardId[boardView.board.boardId];
        final boardCanModifyItems =
            boardPermissionProfile?.has(BoardCapability.modifyItems) ??
                canModifyItems;
        final boardCanManage =
            boardPermissionProfile?.has(BoardCapability.manageBoard) ??
                canManageBoard;
        final boardColumns = [...snapshot.columns]
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
        final itemsById = boardItemsById[boardId] ?? const <String, WorkItem>{};
        final goalColors = boardGoalColors[boardId] ?? const <String, int>{};
        final showBoardSection =
            tileItems.isNotEmpty || boardView.isActiveBoard;
        if (!showBoardSection) continue;

        if (laneChildren.isNotEmpty) {
          laneChildren.add(const SizedBox(height: 10));
        }

        if (hasMultipleBoards) {
          laneChildren.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: boardView.isActiveBoard
                          ? null
                          : () {
                              ref
                                  .read(boardControllerProvider)
                                  .switchBoard(boardId);
                            },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        child: Text(
                          boardView.board.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                    ),
                  ),
                  if (boardView.isActiveBoard)
                    const Chip(
                      label: Text('Active'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
          );
        }

        if (tileItems.isEmpty) {
          laneChildren.add(
            DragTarget<WorkItem>(
              onWillAcceptWithDetails: (details) {
                return boardCanModifyItems &&
                    details.data.boardId == boardId &&
                    details.data.columnId != boardColumn.columnId;
              },
              onAcceptWithDetails: (details) {
                if (!boardCanModifyItems) {
                  _showActionFeedback(
                    context,
                    'Select this board first to change its items.',
                  );
                  return;
                }
                _moveItemWithUndo(
                  context,
                  ref,
                  item: details.data,
                  toColumnId: boardColumn.columnId,
                );
              },
              builder: (context, candidateData, rejectedData) {
                final isDropActive = candidateData.any(
                  (item) =>
                      item != null &&
                      item.boardId == boardId &&
                      item.columnId != boardColumn.columnId,
                );
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: isDropActive
                        ? Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.35)
                        : null,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDropActive
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      boardCanModifyItems ? 'Drop item here' : 'No items',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                );
              },
            ),
          );
          continue;
        }

        laneChildren.addAll([
          _buildReorderGapTarget(
            context,
            ref,
            enabled: boardCanModifyItems,
            boardId: boardId,
            beforeItemId: null,
            afterItemId: tileItems.first.itemId,
            toColumnId: boardColumn.columnId,
            thickness: 8,
            margin: const EdgeInsets.only(bottom: 2),
          ),
          for (var index = 0; index < tileItems.length; index++) ...[
            (() {
              final item = tileItems[index];
              return BoardItemTile(
                item: item,
                columns: boardColumns,
                allItems: snapshot.items,
                density: density,
                parentPathMode:
                    snapshot.board.validationSettings.hierarchyParentPathMode,
                focused: focusedItemId == item.itemId,
                selected: selectedItemIds.contains(item.itemId),
                childCount: snapshot.items
                    .where((x) => x.parentId == item.itemId)
                    .length,
                onSelect: () {
                  _focusItem(ref, item: item);
                },
                onAddChildAction: () {
                  _showSmartChildCreateDialog(
                    context,
                    ref,
                    parent: item,
                    canManageBoard: boardCanManage,
                  );
                },
                onEdit: () {
                  _showEditItemSheet(
                    context,
                    ref,
                    item: item,
                    allItems: snapshot.items,
                    settings: snapshot.board.validationSettings,
                  );
                },
                onViewDetails: () {
                  _showItemDetailsSheet(
                    context,
                    ref,
                    item: item,
                    allItems: snapshot.items,
                    columns: boardColumns,
                    settings: snapshot.board.validationSettings,
                  );
                },
                onToggleArchive: () {
                  _toggleArchiveWithUndo(
                    context,
                    ref,
                    item: item,
                  );
                },
                onMoveToColumn: (toColumnId) => _moveItemWithUndo(
                  context,
                  ref,
                  item: item,
                  toColumnId: toColumnId,
                ),
                onToggleSelected: () => _toggleItemSelection(
                  ref,
                  item.itemId,
                ),
                onReparent: boardCanModifyItems
                    ? () => _showReparentDialog(
                          context,
                          ref,
                          item: item,
                          allItems: snapshot.items,
                        )
                    : null,
                onJumpToParent: item.parentId == null
                    ? null
                    : () {
                        ref.read(boardVisibilityFilterProvider.notifier).state =
                            <WorkItemType>{};
                        _setFocusedItemId(
                          ref,
                          item.parentId,
                          hierarchyItemKey: item.parentId == null
                              ? null
                              : _hierarchyNodeKey(
                                  boardId: item.boardId,
                                  itemId: item.parentId!,
                                ),
                        );
                        ref.read(focusModeEnabledProvider.notifier).state =
                            true;
                      },
                onDelete: boardCanModifyItems
                    ? () => _deleteItemWithUndo(
                          context,
                          ref,
                          item: item,
                          allItems: snapshot.items,
                        )
                    : null,
                canModifyItems: boardCanModifyItems,
                accentColor: (() {
                  final topGoalId = topLevelGoalIdForItem(item, itemsById);
                  final accentColorValue =
                      topGoalId == null ? null : goalColors[topGoalId];
                  return accentColorValue == null
                      ? null
                      : Color(accentColorValue);
                })(),
              );
            })(),
            _buildReorderGapTarget(
              context,
              ref,
              enabled: boardCanModifyItems,
              boardId: boardId,
              beforeItemId: tileItems[index].itemId,
              afterItemId: index + 1 < tileItems.length
                  ? tileItems[index + 1].itemId
                  : null,
              toColumnId: boardColumn.columnId,
              thickness: 8,
              margin: const EdgeInsets.only(bottom: 2),
            ),
          ],
        ]);
      }

      if (children.isNotEmpty) {
        children.add(const SizedBox(width: 12));
      }

      children.add(
        SizedBox(
          width: columnWidth,
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: compactDensity ? 4 : 8,
              horizontal: compactDensity ? 2 : 4,
            ),
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(compactDensity ? 8 : 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Tooltip(
                            message: lane.displayColumn.name,
                            child: Text(
                              lane.displayColumn.name,
                              maxLines: compactDensity ? 2 : 3,
                              overflow: TextOverflow.ellipsis,
                              style: compactDensity
                                  ? Theme.of(context).textTheme.titleSmall
                                  : Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ),
                        if (hasMultipleBoards)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Chip(
                              label: Text(
                                  '${lane.columnsByBoardId.length} boards'),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '$totalVisibleItems item(s)',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    Expanded(
                      child: Container(
                        key: ValueKey(
                          'multi-board-kanban-lane-content-${lane.displayColumn.name}',
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: laneChildren.isEmpty
                            ? Center(
                                child: Text(
                                  'No items',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              )
                            : ListView(
                                padding: const EdgeInsets.all(6),
                                children: laneChildren,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: children,
    );
  }

  Future<void> _showReparentDialog(
    BuildContext context,
    WidgetRef ref, {
    required WorkItem item,
    required List<WorkItem> allItems,
  }) async {
    String? selectedParentId = item.parentId;
    final candidates = _parentCandidatesForType(
      childType: item.type,
      allItems: allItems,
      currentItemId: item.itemId,
      preserveParentId: item.parentId,
    );

    final submittedParent = await showDialog<String?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Re-parent item'),
            content: DropdownButtonFormField<String?>(
              initialValue: selectedParentId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Parent',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('None (make root item)'),
                ),
                for (final candidate in candidates)
                  DropdownMenuItem<String?>(
                    value: candidate.itemId,
                    child: Text(
                      _parentCandidateLabel(
                        child: item,
                        candidate: candidate,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => selectedParentId = value),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(selectedParentId),
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );

    if (submittedParent == item.parentId) return;
    final updated = await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).reparentItem(
            boardId: item.boardId,
            itemId: item.itemId,
            parentId: submittedParent,
            clearParent: submittedParent == null,
          ),
    );
    if (!updated) return;
    ref.read(boardControllerProvider).stageReparentUndo(
          item: item,
          fromParentId: item.parentId,
          toParentId: submittedParent,
        );
  }

  Future<void> _showBulkMoveDialog(
    BuildContext context,
    WidgetRef ref, {
    required List<BoardColumn> columns,
    required Set<String> selectedItemIds,
  }) async {
    if (columns.isEmpty || selectedItemIds.isEmpty) return;
    var targetColumnId = columns.first.columnId;

    final submitted = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Move ${selectedItemIds.length} selected item(s)'),
          content: DropdownButtonFormField<String>(
            initialValue: targetColumnId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Target column',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final column in columns)
                DropdownMenuItem(
                    value: column.columnId, child: Text(column.name)),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => targetColumnId = value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(targetColumnId),
              child: const Text('Move'),
            ),
          ],
        ),
      ),
    );

    if (submitted == null) return;
    final ok = await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).bulkUpdateItems(
            itemIds: selectedItemIds.toList(),
            toColumnId: submitted,
          ),
    );
    if (ok) {
      ref.read(selectedBoardItemIdsProvider.notifier).state = <String>{};
    }
  }

  Future<void> _showBulkTagDialog(
    BuildContext context,
    WidgetRef ref, {
    required Set<String> selectedItemIds,
    required Iterable<WorkItem> selectedItems,
    required bool remove,
  }) async {
    if (selectedItemIds.isEmpty) return;
    var tagsText = '';

    final submittedTags = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${remove ? 'Remove' : 'Add'} tags for '
            '${selectedItemIds.length} selected item(s)'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'comma,separated,tags',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => tagsText = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final tags = tagsText
                  .split(',')
                  .map((t) => t.trim())
                  .where((t) => t.isNotEmpty)
                  .toList();
              if (tags.isEmpty) return;
              Navigator.of(context).pop(tags);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (submittedTags == null || submittedTags.isEmpty) return;
    await _applyBulkUpdateAcrossBoards(
      context,
      ref,
      items: selectedItems,
      addTags: remove ? const [] : submittedTags,
      removeTags: remove ? submittedTags : const [],
    );
  }

  Future<void> _applyBulkUpdateAcrossBoards(
    BuildContext context,
    WidgetRef ref, {
    required Iterable<WorkItem> items,
    String? toColumnId,
    bool? archived,
    List<String> addTags = const [],
    List<String> removeTags = const [],
  }) async {
    final itemsByBoardId = <String, List<String>>{};
    for (final item in items) {
      itemsByBoardId
          .putIfAbsent(item.boardId, () => <String>[])
          .add(item.itemId);
    }
    for (final entry in itemsByBoardId.entries) {
      final ok = await _runGuardedAction(
        context,
        () => ref.read(boardControllerProvider).bulkUpdateItems(
              boardId: entry.key,
              itemIds: entry.value,
              toColumnId: toColumnId,
              archived: archived,
              addTags: addTags,
              removeTags: removeTags,
            ),
      );
      if (!ok) return;
    }
    ref.read(selectedBoardItemIdsProvider.notifier).state = <String>{};
  }

  Widget _buildAlternativeView({
    required BuildContext context,
    required WidgetRef ref,
    required BoardPlanningView planningView,
    required List<BoardColumn> columns,
    required List<WorkItem> allItems,
    required Set<WorkItemType> filters,
    required BoardItemStateFilter stateFilter,
    required bool focusModeEnabled,
    required Set<String>? focusRelatedItemIds,
    required String textQuery,
    required String tagFilter,
    required Map<String, BoardColumn> columnsById,
    required bool showOverdueOnly,
    required bool showDueSoonOnly,
    required bool showArchivedOnly,
    required String? focusedItemId,
    required String? selectedHierarchyItemId,
    required bool canModifyItems,
    required bool canManageBoard,
    required Set<String> collapsedHierarchyItemIds,
    required Set<String> selectedItemIds,
    required BoardCardDensity density,
    required BoardValidationSettings settings,
    Map<String, List<BoardColumn>>? columnsByBoardId,
    Map<String, List<WorkItem>>? itemsByBoardId,
    Map<String, BoardValidationSettings>? settingsByBoardId,
    Map<String, BoardPermissionProfile>? permissionProfilesByBoardId,
  }) {
    final hierarchyColorEnabled = settings.hierarchyColorGroupingByGoal;
    final goalColors = hierarchyColorEnabled
        ? resolveGoalColors(
            items: allItems,
            overrides: settings.hierarchyGoalColorOverrides,
          )
        : const <String, int>{};
    final goalColorsByBoardId = <String, Map<String, int>>{
      for (final entry
          in (settingsByBoardId ?? const <String, BoardValidationSettings>{})
              .entries)
        if (entry.value.hierarchyColorGroupingByGoal)
          entry.key: resolveGoalColors(
            items: itemsByBoardId?[entry.key] ??
                allItems.where((item) => item.boardId == entry.key),
            overrides: entry.value.hierarchyGoalColorOverrides,
          ),
    };

    final hierarchyFullTreeMode = planningView == BoardPlanningView.hierarchy;
    final visibleItems = hierarchyFullTreeMode
        ? allItems
            .where(
              (item) =>
                  !item.isInbox &&
                  (showArchivedOnly ? item.archived : !item.archived),
            )
            .toList(growable: false)
        : _sharedVisibleItems(
            items: allItems,
            filters: filters,
            stateFilter: stateFilter,
            focusModeEnabled: focusModeEnabled,
            focusRelatedItemIds: focusRelatedItemIds,
            textQuery: textQuery,
            tagFilter: tagFilter,
            columnsById: columnsById,
            showOverdueOnly: showOverdueOnly,
            showDueSoonOnly: showDueSoonOnly,
            showArchivedOnly: showArchivedOnly,
          );

    Widget buildItemCard(
      WorkItem item, {
      double indent = 0,
      int hierarchyDepth = 0,
      bool showHierarchyGuides = false,
      bool hasChildren = false,
      bool isCollapsed = false,
      VoidCallback? onToggleCollapsed,
    }) {
      final compactDensity = density == BoardCardDensity.compact;
      final itemPermissionProfile = permissionProfilesByBoardId?[item.boardId];
      final itemCanModifyItems = itemPermissionProfile
              ?.has(BoardCapability.modifyItems) ??
          (canModifyItems && item.boardId == ref.read(currentBoardIdProvider));
      final itemCanManageBoard = itemPermissionProfile
              ?.has(BoardCapability.manageBoard) ??
          (canManageBoard && item.boardId == ref.read(currentBoardIdProvider));
      final itemColumns = columnsByBoardId?[item.boardId] ?? columns;
      final itemAllItems = itemsByBoardId?[item.boardId] ??
          allItems.where((entry) => entry.boardId == item.boardId).toList();
      final itemSettings = settingsByBoardId?[item.boardId] ?? settings;
      final itemItemsById = {
        for (final entry in itemAllItems) entry.itemId: entry
      };
      final itemGoalColors = goalColorsByBoardId[item.boardId] ?? goalColors;
      final itemHierarchyColorEnabled = settingsByBoardId == null
          ? hierarchyColorEnabled
          : itemSettings.hierarchyColorGroupingByGoal;
      final topGoalId = itemHierarchyColorEnabled
          ? topLevelGoalIdForItem(item, itemItemsById)
          : null;
      final accentColorValue =
          topGoalId == null ? null : itemGoalColors[topGoalId];
      final accentColor =
          accentColorValue == null ? null : Color(accentColorValue);
      final tile = BoardItemTile(
        key: ValueKey('board-item-tile-${item.boardId}-${item.itemId}'),
        item: item,
        columns: itemColumns,
        allItems: itemAllItems,
        focused: hierarchyFullTreeMode
            ? selectedHierarchyItemId == _hierarchyNodeKeyForItem(item)
            : focusedItemId == item.itemId,
        selected: selectedItemIds.contains(item.itemId),
        childCount:
            itemAllItems.where((entry) => entry.parentId == item.itemId).length,
        onSelect: () {
          _focusItem(
            ref,
            item: item,
          );
        },
        onToggleSelected: () => _toggleItemSelection(ref, item.itemId),
        onAddChildAction: () {
          _showSmartChildCreateDialog(
            context,
            ref,
            parent: item,
            canManageBoard: itemCanManageBoard,
          );
        },
        onEdit: () {
          _showEditItemSheet(
            context,
            ref,
            item: item,
            allItems: itemAllItems,
            settings: itemSettings,
          );
        },
        onViewDetails: () {
          _showItemDetailsSheet(
            context,
            ref,
            item: item,
            allItems: itemAllItems,
            columns: itemColumns,
            settings: itemSettings,
          );
        },
        onToggleArchive: () {
          _toggleArchiveWithUndo(context, ref, item: item);
        },
        density: density,
        allowDrag: itemCanModifyItems,
        showCompactParentSubtitle: showHierarchyGuides,
        parentPathMode: itemSettings.hierarchyParentPathMode,
        onMoveToColumn: (toColumnId) => _moveItemWithUndo(
          context,
          ref,
          item: item,
          toColumnId: toColumnId,
        ),
        onReparent: itemCanModifyItems
            ? () => _showReparentDialog(
                  context,
                  ref,
                  item: item,
                  allItems: itemAllItems,
                )
            : null,
        onDelete: itemCanModifyItems
            ? () => _deleteItemWithUndo(
                  context,
                  ref,
                  item: item,
                  allItems: itemAllItems,
                )
            : null,
        onJumpToParent: item.parentId == null
            ? null
            : () {
                ref.read(boardVisibilityFilterProvider.notifier).state =
                    <WorkItemType>{};
                _setFocusedItemId(
                  ref,
                  item.parentId,
                  hierarchyItemKey: item.parentId == null
                      ? null
                      : _hierarchyNodeKey(
                          boardId: item.boardId,
                          itemId: item.parentId!,
                        ),
                );
                ref.read(focusModeEnabledProvider.notifier).state = true;
              },
        canModifyItems: itemCanModifyItems,
        accentColor: accentColor,
        onLongPress: showHierarchyGuides ? null : onToggleCollapsed,
      );

      final chevronSlotWidth = compactDensity ? 20.0 : 22.0;
      final guidedTile = !showHierarchyGuides || hierarchyDepth <= 0
          ? tile
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: SizedBox(
                      width: hierarchyDepth * 10.0 + 12,
                      child: CustomPaint(
                        painter: _HierarchyGuidePainter(
                          depth: hierarchyDepth,
                          color: (accentColor ??
                                  Theme.of(context).colorScheme.outlineVariant)
                              .withValues(
                            alpha: compactDensity ? 0.75 : 0.55,
                          ),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: chevronSlotWidth,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: hasChildren
                          ? Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: InkWell(
                                onTap: onToggleCollapsed,
                                borderRadius: BorderRadius.circular(10),
                                child: Icon(
                                  isCollapsed
                                      ? Icons.chevron_right
                                      : Icons.expand_more,
                                  size: compactDensity ? 16 : 18,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                  Expanded(child: tile),
                ],
              ),
            );
      return Padding(
        padding: EdgeInsets.only(
          left: showHierarchyGuides ? 0 : indent,
          right: compactDensity
              ? (showHierarchyGuides ? 2 : 4)
              : (showHierarchyGuides ? 4 : 8),
          bottom: compactDensity
              ? (showHierarchyGuides ? 1 : 2)
              : (showHierarchyGuides ? 3 : 6),
        ),
        child: guidedTile,
      );
    }

    List<Widget> buildLinearReorderRows(List<WorkItem> orderedItems) {
      if (orderedItems.isEmpty) {
        return const <Widget>[];
      }
      final currentActiveBoardId = ref.read(currentBoardIdProvider);
      final rows = <Widget>[
        _buildReorderGapTarget(
          context,
          ref,
          enabled: canModifyItems &&
              orderedItems.first.boardId == currentActiveBoardId,
          boardId: orderedItems.first.boardId,
          beforeItemId: null,
          afterItemId: orderedItems.first.itemId,
          thickness: 8,
          margin: const EdgeInsets.only(bottom: 2),
        ),
      ];
      for (var index = 0; index < orderedItems.length; index++) {
        final item = orderedItems[index];
        rows.add(buildItemCard(item));
        final nextItem =
            index + 1 < orderedItems.length ? orderedItems[index + 1] : null;
        final gapBoardId = nextItem?.boardId ?? item.boardId;
        final sameBoardGap =
            nextItem == null || nextItem.boardId == item.boardId;
        rows.add(
          _buildReorderGapTarget(
            context,
            ref,
            enabled: canModifyItems &&
                gapBoardId == currentActiveBoardId &&
                sameBoardGap,
            boardId: gapBoardId,
            beforeItemId: item.itemId,
            afterItemId: nextItem?.itemId,
            thickness: 8,
            margin: const EdgeInsets.only(bottom: 2),
          ),
        );
      }
      return rows;
    }

    if (visibleItems.isEmpty) {
      return const Center(child: Text('No items match current filters.'));
    }

    if (planningView == BoardPlanningView.backlog) {
      final backlogKinds = {
        BoardColumnKind.planning,
        BoardColumnKind.backlog,
        BoardColumnKind.ready,
      };
      final backlogItems = visibleItems.where((item) {
        final kind = columnsById[item.columnId]?.kind;
        return backlogKinds.contains(kind);
      }).toList();

      return ListView(
        padding: const EdgeInsets.all(8),
        children: buildLinearReorderRows(backlogItems),
      );
    }

    if (planningView == BoardPlanningView.focus) {
      final now = DateTime.now();
      final soon = now.add(const Duration(days: 7));
      final flagged = visibleItems.where((item) {
        final column = columnsById[item.columnId];
        final isBlocked = column?.isBlockedState == true;
        final isUrgent = column?.kind == BoardColumnKind.urgent;
        final isOverdue = item.dueAt != null &&
            item.completedAt == null &&
            item.dueAt!.isBefore(now);
        final isDueSoon = item.dueAt != null &&
            item.completedAt == null &&
            !item.dueAt!.isBefore(now) &&
            !item.dueAt!.isAfter(soon);
        return isBlocked || isUrgent || isOverdue || isDueSoon;
      }).toList();

      return ListView(
        padding: const EdgeInsets.all(8),
        children: [
          Text('Focus queue (${flagged.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...buildLinearReorderRows(flagged),
        ],
      );
    }

    // Hierarchy view.
    final byId = {
      for (final item in visibleItems) _hierarchyNodeKeyForItem(item): item,
    };
    final childrenByParent = <String?, List<WorkItem>>{};
    for (final item in visibleItems) {
      final parentKey = item.parentId == null
          ? null
          : _hierarchyNodeKey(boardId: item.boardId, itemId: item.parentId!);
      final scopedParentKey =
          parentKey != null && byId.containsKey(parentKey) ? parentKey : null;
      childrenByParent.putIfAbsent(scopedParentKey, () => []).add(item);
    }

    void sortByPriority(List<WorkItem> items) {
      items.sort((a, b) {
        final bySortOrder = a.sortOrder.compareTo(b.sortOrder);
        if (bySortOrder != 0) return bySortOrder;
        final byType = _typeRank(a.type).compareTo(_typeRank(b.type));
        if (byType != 0) return byType;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    }

    for (final entry in childrenByParent.values) {
      sortByPriority(entry);
    }

    Set<String> collectBranchItemIds(String rootItemId) {
      final collected = <String>{rootItemId};
      final pending = <String>[rootItemId];
      while (pending.isNotEmpty) {
        final current = pending.removeLast();
        for (final child in childrenByParent[current] ?? const <WorkItem>[]) {
          final childKey = _hierarchyNodeKeyForItem(child);
          if (collected.add(childKey)) {
            pending.add(childKey);
          }
        }
      }
      return collected;
    }

    List<Widget> buildTreeFromNodes(
      List<WorkItem> nodes,
      int depth,
      Set<String> activePath, {
      required String? parentId,
      Set<String>? renderedItemIds,
    }) {
      // When the collapsed set is empty, this DFS renders the full reachable
      // hierarchy exactly once. Cycle guards stay local to the active branch so
      // expand-all can never reduce what is visible.
      final rows = <Widget>[];
      final candidateNodes = <WorkItem>[];
      for (final node in nodes) {
        final nodeKey = _hierarchyNodeKeyForItem(node);
        if (activePath.contains(nodeKey)) continue;
        if (renderedItemIds != null && renderedItemIds.contains(nodeKey)) {
          continue;
        }
        candidateNodes.add(node);
      }
      if (candidateNodes.isEmpty) {
        return rows;
      }

      final currentActiveBoardId = ref.read(currentBoardIdProvider);
      final boardId = candidateNodes.first.boardId;
      final canReorderGroup = canModifyItems && boardId == currentActiveBoardId;

      rows.add(
        _buildReorderGapTarget(
          context,
          ref,
          enabled: canReorderGroup,
          boardId: boardId,
          beforeItemId: null,
          afterItemId: candidateNodes.first.itemId,
          parentId: parentId,
          clearParent: parentId == null,
          thickness: 8,
          margin: EdgeInsets.only(left: depth > 0 ? 10 : 0, bottom: 2),
        ),
      );

      for (var index = 0; index < candidateNodes.length; index++) {
        final node = candidateNodes[index];
        final nodeKey = _hierarchyNodeKeyForItem(node);
        renderedItemIds?.add(nodeKey);
        final childNodes = childrenByParent[nodeKey] ?? const <WorkItem>[];
        final hasChildren = childNodes.isNotEmpty;
        final isCollapsed = collapsedHierarchyItemIds.contains(nodeKey);
        final row = buildItemCard(
          node,
          hierarchyDepth: depth,
          showHierarchyGuides: true,
          hasChildren: hasChildren,
          isCollapsed: isCollapsed,
          onToggleCollapsed: !hasChildren
              ? null
              : () {
                  final next = <String>{...collapsedHierarchyItemIds};
                  if (!next.add(nodeKey)) {
                    next.remove(nodeKey);
                  }
                  unawaited(
                    ref
                        .read(boardControllerProvider)
                        .setCollapsedHierarchyItemIds(next),
                  );
                },
        );
        final wrappedRow = DragTarget<WorkItem>(
          onWillAcceptWithDetails: (details) {
            if (!canReorderGroup) return false;
            if (details.data.boardId != node.boardId) return false;
            if (details.data.itemId == node.itemId) return false;
            return true;
          },
          onAcceptWithDetails: (details) {
            final lastChildId =
                childNodes.isEmpty ? null : childNodes.last.itemId;
            unawaited(
              _reorderItemFromDrop(
                context,
                ref,
                item: details.data,
                boardId: node.boardId,
                parentId: node.itemId,
                beforeItemId: lastChildId,
                afterItemId: null,
              ),
            );
          },
          builder: (context, candidateData, rejectedData) {
            final isDropActive = candidateData.any(
              (item) => item != null && item.boardId == node.boardId,
            );
            return AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDropActive
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                ),
              ),
              child: row,
            );
          },
        );
        rows.add(wrappedRow);
        if (!isCollapsed) {
          rows.addAll(
            buildTreeFromNodes(
              childNodes,
              depth + 1,
              <String>{...activePath, nodeKey},
              parentId: node.itemId,
              renderedItemIds: renderedItemIds,
            ),
          );
        }
        final nextSiblingId = index + 1 < candidateNodes.length
            ? candidateNodes[index + 1].itemId
            : null;
        rows.add(
          _buildReorderGapTarget(
            context,
            ref,
            enabled: canReorderGroup,
            boardId: boardId,
            beforeItemId: node.itemId,
            afterItemId: nextSiblingId,
            parentId: parentId,
            clearParent: parentId == null,
            thickness: 8,
            margin: EdgeInsets.only(left: depth > 0 ? 10 : 0, bottom: 2),
          ),
        );
      }
      return rows;
    }

    final unreachableItemIds =
        HierarchyContextPolicy.findUnreachableItemIds(items: visibleItems);
    final rootNodes = childrenByParent[null] ?? const <WorkItem>[];
    final mainRows = buildTreeFromNodes(
      rootNodes,
      0,
      <String>{},
      parentId: null,
    );
    final focusedHierarchyItem =
        selectedHierarchyItemId == null ? null : byId[selectedHierarchyItemId];
    final focusedHierarchyHasChildren = focusedHierarchyItem != null &&
        (childrenByParent[_hierarchyNodeKeyForItem(focusedHierarchyItem)] ??
                const <WorkItem>[])
            .isNotEmpty;
    final focusedBranchItemIds = focusedHierarchyItem == null
        ? const <String>{}
        : collectBranchItemIds(_hierarchyNodeKeyForItem(focusedHierarchyItem));
    final focusedBranchHasCollapsedNodes = focusedBranchItemIds.any(
      collapsedHierarchyItemIds.contains,
    );
    final focusedHierarchyItemKey = focusedHierarchyItem == null
        ? null
        : _hierarchyNodeKeyForItem(focusedHierarchyItem);
    final VoidCallback? expandSelectedHierarchyBranch =
        focusedHierarchyItem == null ||
                !focusedHierarchyHasChildren ||
                !focusedBranchHasCollapsedNodes
            ? null
            : () {
                final next = <String>{
                  ...collapsedHierarchyItemIds,
                }..removeWhere(focusedBranchItemIds.contains);
                unawaited(
                  ref
                      .read(boardControllerProvider)
                      .setCollapsedHierarchyItemIds(next),
                );
              };
    final VoidCallback? collapseSelectedHierarchyBranch =
        focusedHierarchyItem == null ||
                !focusedHierarchyHasChildren ||
                collapsedHierarchyItemIds.contains(focusedHierarchyItemKey)
            ? null
            : () {
                unawaited(
                  ref
                      .read(boardControllerProvider)
                      .setCollapsedHierarchyItemIds(<String>{
                    ...collapsedHierarchyItemIds,
                    focusedHierarchyItemKey!,
                  }),
                );
              };
    final showSelectedBranchOverlay = focusedHierarchyItem != null &&
        focusedHierarchyHasChildren &&
        (expandSelectedHierarchyBranch != null ||
            collapseSelectedHierarchyBranch != null);
    final recoveredRootNodes = visibleItems
        .where((item) => unreachableItemIds.contains(item.itemId))
        .toList();
    sortByPriority(recoveredRootNodes);
    final recoveredCount = recoveredRootNodes.length;

    final recoveredRows = <Widget>[];
    final recoveredRenderedItemIds = <String>{};
    for (final node in recoveredRootNodes) {
      recoveredRows.addAll(
        buildTreeFromNodes(
          [node],
          0,
          <String>{},
          parentId: null,
          renderedItemIds: recoveredRenderedItemIds,
        ),
      );
    }

    Widget buildFloatingBranchControl({
      required Key key,
      required String tooltip,
      required IconData icon,
      required VoidCallback onTap,
    }) {
      return Tooltip(
        message: tooltip,
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 20),
          ),
        ),
      );
    }

    return SizedBox.expand(
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (ref.read(selectedHierarchyItemIdProvider) == null &&
                  ref.read(focusedItemIdProvider) == null) {
                return;
              }
              ref.read(boardControllerProvider).clearFocusedItem();
            },
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Expanded(child: SizedBox(height: 36)),
                      const SizedBox(width: 8),
                      AppHelpTarget(
                        spec: _workspaceHierarchyControlsHelpSpec(),
                        borderRadius: BorderRadius.circular(12),
                        child: TapRegion(
                          groupId: boardItemFocusTapRegionGroup,
                          child: Wrap(
                            spacing: 2,
                            children: [
                              IconButton(
                                tooltip: focusedHierarchyItem == null
                                    ? 'Expand all branches'
                                    : 'Expand selected branch',
                                onPressed: focusedHierarchyItem == null
                                    ? (collapsedHierarchyItemIds.isEmpty
                                        ? null
                                        : () {
                                            unawaited(
                                              ref
                                                  .read(
                                                boardControllerProvider,
                                              )
                                                  .setCollapsedHierarchyItemIds(
                                                <String>{},
                                              ),
                                            );
                                          })
                                    : expandSelectedHierarchyBranch,
                                icon: const Icon(Icons.unfold_more),
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints.tightFor(
                                  width: 32,
                                  height: 32,
                                ),
                                padding: EdgeInsets.zero,
                              ),
                              IconButton(
                                tooltip: focusedHierarchyItem == null
                                    ? 'Collapse all branches'
                                    : 'Collapse selected branch',
                                onPressed: focusedHierarchyItem == null
                                    ? () {
                                        unawaited(
                                          ref
                                              .read(boardControllerProvider)
                                              .setCollapsedHierarchyItemIds({
                                            for (final entry in byId.values)
                                              if ((childrenByParent[
                                                          _hierarchyNodeKeyForItem(
                                                              entry)] ??
                                                      const <WorkItem>[])
                                                  .isNotEmpty)
                                                _hierarchyNodeKeyForItem(entry),
                                          }),
                                        );
                                      }
                                    : collapseSelectedHierarchyBranch,
                                icon: const Icon(Icons.unfold_less),
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints.tightFor(
                                  width: 32,
                                  height: 32,
                                ),
                                padding: EdgeInsets.zero,
                              ),
                              IconButton(
                                tooltip: 'Clear selected item',
                                onPressed: focusedHierarchyItem == null
                                    ? null
                                    : () {
                                        ref
                                            .read(boardControllerProvider)
                                            .clearFocusedItem();
                                      },
                                icon: const Icon(Icons.close),
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints.tightFor(
                                  width: 32,
                                  height: 32,
                                ),
                                padding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                AppHelpTarget(
                  spec: const AppHelpTargetSpec(
                    id: AppHelpTargetIds.workspaceHierarchySurface,
                    title: 'Hierarchy view',
                    description:
                        'Hierarchy shows how goals, projects, tasks, and actions connect to each other.',
                    whenToUse:
                        'Use it when you want to understand structure, check parent-child relationships, or work down from larger goals.',
                    whatHappens:
                        'Selecting an item helps you follow its branch, expand or collapse context, and understand how work rolls up.',
                    icon: Icons.account_tree_outlined,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  child: Column(
                    children: [
                      if (recoveredCount > 0)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .errorContainer
                                .withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 18,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Recovered $recoveredCount item(s) with invalid or cyclic hierarchy data and surfaced them separately so they do not disappear or crash the view.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onErrorContainer,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ...mainRows,
                      if (recoveredRows.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                          child: Text(
                            'Recovered branches',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        ...recoveredRows,
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (showSelectedBranchOverlay)
            Positioned(
              right: 12,
              top: 52,
              child: Material(
                elevation: 4,
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (expandSelectedHierarchyBranch != null)
                        buildFloatingBranchControl(
                          key: const ValueKey(
                            'hierarchy-overlay-expand-branch',
                          ),
                          tooltip: 'Expand this branch',
                          onTap: expandSelectedHierarchyBranch,
                          icon: Icons.unfold_more,
                        ),
                      if (collapseSelectedHierarchyBranch != null)
                        buildFloatingBranchControl(
                          key: const ValueKey(
                            'hierarchy-overlay-collapse-branch',
                          ),
                          tooltip: 'Collapse this branch',
                          onTap: collapseSelectedHierarchyBranch,
                          icon: Icons.unfold_less,
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardAsync = ref.watch(boardStreamProvider);
    final permissionProfile = ref.watch(boardPermissionProfileProvider);
    final canModifyItems =
        permissionProfile?.has(BoardCapability.modifyItems) ?? false;
    final canManageBoard =
        permissionProfile?.has(BoardCapability.manageBoard) ?? false;
    final boardsAsync = ref.watch(boardsProvider);
    final currentBoardId = ref.watch(currentBoardIdProvider);
    final visibilityFilter = ref.watch(boardVisibilityFilterProvider);
    final planningView = ref.watch(boardPlanningViewProvider);
    final calendarSubview = ref.watch(boardCalendarSubviewProvider);
    final calendarVisibleKinds =
        ref.watch(boardCalendarVisibleDateKindsProvider);
    final showCalendarUnscheduled =
        ref.watch(boardCalendarShowUnscheduledProvider);
    final calendarAnchorDate = ref.watch(boardCalendarAnchorDateProvider);
    final collapsedHierarchyItemIds =
        ref.watch(collapsedHierarchyItemIdsProvider);
    final stateFilter = ref.watch(boardItemStateFilterProvider);
    final tagFilter = ref.watch(boardTagFilterProvider);
    final selectedItemIds = ref.watch(selectedBoardItemIdsProvider);
    final focusedItemId = ref.watch(focusedItemIdProvider);
    final selectedHierarchyItemId = ref.watch(selectedHierarchyItemIdProvider);
    final focusModeEnabled = ref.watch(focusModeEnabledProvider);
    final textQuery = ref.watch(boardTextQueryProvider);
    final searchExpanded = ref.watch(workspaceSearchExpandedProvider);
    final workspaceSurface = ref.watch(boardWorkspaceSurfaceProvider);
    final selectedBoardIds = ref.watch(workspaceSelectedBoardIdsProvider);
    final showOverdueOnly = ref.watch(showOverdueOnlyProvider);
    final showDueSoonOnly = ref.watch(showDueSoonOnlyProvider);
    final showArchivedOnly = ref.watch(showArchivedOnlyProvider);
    final cardDensity = ref.watch(boardCardDensityProvider);
    final lastAutoFocusedDoingBoardId =
        ref.watch(lastAutoFocusedDoingBoardIdProvider);
    final pendingUndoOperation = ref.watch(pendingBoardUndoOperationProvider);
    final feedbackQueue = ref.watch(workspaceFeedbackQueueProvider);
    ref.watch(boardFilterPresetsProvider);
    final activeDraggedItem = ref.watch(activeDraggedItemProvider);
    final remindersAsync = ref.watch(boardActiveRemindersProvider);
    final systemNotices = ref.watch(workspaceVisibleSystemNoticesProvider);
    final topAttentionNotice =
        ref.watch(workspaceTopAttentionNoticeProvider).valueOrNull;
    final inboxCount =
        boardAsync.valueOrNull?.items.where((item) => item.isInbox).length ?? 0;
    final activeFilterCount = _activeWorkspaceFilterCount(
      planningView: planningView,
      typeFilters: visibilityFilter,
      stateFilter: stateFilter,
      tagFilter: tagFilter,
      showOverdueOnly: showOverdueOnly,
      showDueSoonOnly: showDueSoonOnly,
      showArchivedOnly: showArchivedOnly,
      calendarVisibleKinds: calendarVisibleKinds,
      showCalendarUnscheduled: showCalendarUnscheduled,
    );
    final toolsNeedAttention = inboxCount > 0 ||
        (remindersAsync.valueOrNull?.isNotEmpty ?? false) ||
        systemNotices.isNotEmpty;
    final scopeUserId = ref.watch(boardScopeUserIdProvider);

    return AppPrimaryScaffold(
      activeRoute: AppRoutes.workspace,
      title: 'Workspace',
      helpSurface: AppHelpSurfaceId.workspace,
      workspaceIcon: boardPlanningViewIcon(planningView),
      workspaceSelectedIcon: boardPlanningViewSelectedIcon(planningView),
      onActiveDestinationTap: () {
        ref
            .read(boardControllerProvider)
            .setPlanningView(_nextPlanningView(planningView));
      },
      actions: [
        IconButton(
          key: const ValueKey('open-ai-planning'),
          tooltip: useFirebaseAi ? 'Plan with AI' : 'AI planning setup',
          onPressed: () =>
              Navigator.of(context).pushNamed(AppRoutes.aiPlanning),
          icon: const Icon(Icons.auto_awesome_outlined),
        ),
        AppHelpTarget(
          spec: _workspaceTopFocusHelpSpec(),
          borderRadius: BorderRadius.circular(12),
          child: TapRegion(
            groupId: boardItemFocusTapRegionGroup,
            child: IconButton(
              tooltip: 'Focus view',
              onPressed: () {
                ref
                    .read(boardControllerProvider)
                    .setPlanningView(BoardPlanningView.focus);
              },
              icon: Badge(
                isLabelVisible: planningView == BoardPlanningView.focus,
                smallSize: 9,
                child: Icon(
                  planningView == BoardPlanningView.focus
                      ? Icons.filter_center_focus
                      : Icons.filter_center_focus_outlined,
                ),
              ),
            ),
          ),
        ),
        AppHelpTarget(
          spec: _workspaceTopToolsHelpSpec(),
          borderRadius: BorderRadius.circular(12),
          child: TapRegion(
            groupId: boardItemFocusTapRegionGroup,
            child: IconButton(
              tooltip: 'Workspace tools',
              onPressed: () => _showWorkspaceToolsSurface(context),
              icon: Badge(
                isLabelVisible: toolsNeedAttention,
                child: const Icon(Icons.tune),
              ),
            ),
          ),
        ),
      ],
      floatingActionButton: TapRegion(
        groupId: boardItemFocusTapRegionGroup,
        child: FloatingActionButton.extended(
          onPressed: canModifyItems
              ? () => workspaceSurface == BoardWorkspaceSurface.inbox
                  ? _showQuickCaptureDialog(context, ref)
                  : _showCreateItemDialog(
                      context,
                      ref,
                      canManageBoard: canManageBoard,
                    )
              : () => _showActionFeedback(
                    context,
                    'Current role cannot create items in this board.',
                  ),
          icon: Icon(workspaceSurface == BoardWorkspaceSurface.inbox
              ? Icons.flash_on_outlined
              : Icons.add),
          label: Text(workspaceSurface == BoardWorkspaceSurface.inbox
              ? 'Quick Capture'
              : 'Add Item'),
        ),
      ),
      body: boardAsync.when(
        data: (snapshot) {
          final boards = boardsAsync.valueOrNull ?? const [];
          final columns = [...snapshot.columns]
            ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
          final columnsById = {
            for (final column in columns) column.columnId: column,
          };
          final allItemsById = {
            for (final entry in snapshot.items) entry.itemId: entry,
          };
          final hierarchyColorEnabled =
              snapshot.board.validationSettings.hierarchyColorGroupingByGoal;
          final goalColors = hierarchyColorEnabled
              ? resolveGoalColors(
                  items: snapshot.items,
                  overrides: snapshot
                      .board.validationSettings.hierarchyGoalColorOverrides,
                )
              : const <String, int>{};
          final allBoardIds = boards.isEmpty
              ? {snapshot.board.boardId}
              : {for (final board in boards) board.boardId};
          final visibleBoardIds = selectedBoardIds.isEmpty
              ? allBoardIds
              : allBoardIds.intersection(selectedBoardIds);
          if (!visibleBoardIds.contains(currentBoardId) &&
              visibleBoardIds.isNotEmpty) {
            final fallbackBoardId = boards
                .where((board) => visibleBoardIds.contains(board.boardId))
                .map((board) => board.boardId)
                .first;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(boardControllerProvider).switchBoard(fallbackBoardId);
            });
          }
          final visibleBoards = boards.isEmpty
              ? <Board>[snapshot.board]
              : boards
                  .where((board) => visibleBoardIds.contains(board.boardId))
                  .toList(growable: false);
          final visibleBoardSnapshots = {
            for (final board in visibleBoards)
              board.boardId: board.boardId == snapshot.board.boardId
                  ? boardAsync
                  : ref.watch(boardSnapshotProvider(board.boardId)),
          };
          final visibleBoardError = visibleBoardSnapshots.values
              .where((value) => value.hasError)
              .cast<AsyncError<BoardSnapshot>?>()
              .firstWhere((_) => true, orElse: () => null);
          if (visibleBoardError != null) {
            return Center(
              child: Text(
                'Unable to load selected boards: ${visibleBoardError.error}',
              ),
            );
          }
          final loadingBoards = visibleBoards
              .where((board) =>
                  !(visibleBoardSnapshots[board.boardId]?.hasValue ?? false))
              .toList(growable: false);
          if (loadingBoards.isNotEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          final boardViews = [
            for (final board in visibleBoards)
              _WorkspaceBoardViewData(
                board: board,
                snapshot: visibleBoardSnapshots[board.boardId]!.value!,
                isActiveBoard: board.boardId == currentBoardId,
              ),
          ];
          final multiBoardScope = boardViews.length > 1;
          final mergedItems = [
            for (final boardView in boardViews) ...boardView.snapshot.items,
          ];
          final mergedColumns = [
            for (final boardView in boardViews) ...boardView.snapshot.columns,
          ];
          final mergedColumnsById = {
            for (final column in mergedColumns) column.columnId: column,
          };
          final itemsByBoardId = {
            for (final boardView in boardViews)
              boardView.board.boardId: boardView.snapshot.items,
          };
          final columnsByBoardId = {
            for (final boardView in boardViews)
              boardView.board.boardId: [...boardView.snapshot.columns]
                ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex)),
          };
          final settingsByBoardId = {
            for (final boardView in boardViews)
              boardView.board.boardId:
                  boardView.snapshot.board.validationSettings,
          };
          final accentColorValuesByItemKey = _resolveItemAccentColorValues(
            itemsByBoardId: itemsByBoardId,
            settingsByBoardId: settingsByBoardId,
          );
          final boardNamesById = {
            for (final boardView in boardViews)
              boardView.board.boardId: boardView.board.name,
          };
          final permissionProfilesByBoardId = {
            for (final boardView in boardViews)
              boardView.board.boardId: BoardPermissions.profileFor(
                snapshot: boardView.snapshot,
                userId: scopeUserId,
              ),
          };
          final selectedItemsById = {
            for (final item in mergedItems)
              if (selectedItemIds.contains(item.itemId)) item.itemId: item,
          };
          final focusRelatedItemIds = focusedItemId == null
              ? null
              : _focusRelatedItemIds(mergedItems, focusedItemId);
          final visibleCalendarItems = mergedItems.where((item) {
            return _isVisibleInCurrentModes(
              item: item,
              filters: visibilityFilter,
              stateFilter: stateFilter,
              focusModeEnabled: focusModeEnabled,
              focusRelatedItemIds: focusRelatedItemIds,
              textQuery: textQuery,
              tagFilter: tagFilter,
              columnsById: mergedColumnsById,
              showOverdueOnly: showOverdueOnly,
              showDueSoonOnly: showDueSoonOnly,
              showArchivedOnly: showArchivedOnly,
            );
          }).toList(growable: false);
          final calendarSnapshot = BoardCalendarPolicy.build(
            items: visibleCalendarItems,
            settingsByBoardId: settingsByBoardId,
            boardNamesById: boardNamesById,
            visibleKinds: calendarVisibleKinds,
          );
          final selectedItemBoardIds = {
            for (final item in selectedItemsById.values) item.boardId,
          };
          final bulkActionBoardId = selectedItemBoardIds.length == 1
              ? selectedItemBoardIds.first
              : null;
          final bulkActionColumns = bulkActionBoardId == null
              ? const <BoardColumn>[]
              : (columnsByBoardId[bulkActionBoardId] ?? const <BoardColumn>[]);
          final screenWidth = MediaQuery.sizeOf(context).width;
          final compactDensity = cardDensity == BoardCardDensity.compact;
          const compactLikeWidthFactor = 0.8;
          const compactLikeMinWidth = 230.0;
          const compactLikeMaxWidth = 320.0;
          const compactLikeDesktopWidth = 300.0;
          final columnWidth = screenWidth < 900
              ? (screenWidth * compactLikeWidthFactor)
                  .clamp(compactLikeMinWidth, compactLikeMaxWidth)
              : compactLikeDesktopWidth;
          final doingColumn = columns
              .where((column) => column.kind == BoardColumnKind.inProgress)
              .cast<BoardColumn?>()
              .firstWhere((_) => true, orElse: () => null);
          final doingColumnAnchorKey = GlobalKey();
          final visibleItemsByColumn = {
            for (final column in columns)
              column.columnId: _sortedVisibleItems(
                items: snapshot.items,
                columnId: column.columnId,
                filters: visibilityFilter,
                stateFilter: stateFilter,
                focusModeEnabled: focusModeEnabled,
                focusRelatedItemIds: focusRelatedItemIds,
                textQuery: textQuery,
                tagFilter: tagFilter,
                columnsById: columnsById,
                showOverdueOnly: showOverdueOnly,
                showDueSoonOnly: showDueSoonOnly,
                showArchivedOnly: showArchivedOnly,
              ),
          };
          final shouldAutoFocusDoingColumn = !multiBoardScope &&
              workspaceSurface == BoardWorkspaceSurface.board &&
              planningView == BoardPlanningView.kanban &&
              doingColumn != null &&
              lastAutoFocusedDoingBoardId != currentBoardId;
          if (shouldAutoFocusDoingColumn) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              final anchorContext = doingColumnAnchorKey.currentContext;
              if (anchorContext != null) {
                Scrollable.ensureVisible(
                  anchorContext,
                  alignment: 0.04,
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                );
              }
              ref.read(lastAutoFocusedDoingBoardIdProvider.notifier).state =
                  currentBoardId;
            });
          }

          final dragOverlayColumns = activeDraggedItem == null
              ? null
              : columnsByBoardId[activeDraggedItem.boardId] ??
                  (activeDraggedItem.boardId == currentBoardId
                      ? columns
                      : null);
          final dragOverlayCanModifyItems = activeDraggedItem == null
              ? canModifyItems
              : (permissionProfilesByBoardId[activeDraggedItem.boardId]
                      ?.has(BoardCapability.modifyItems) ??
                  canModifyItems);
          return LayoutBuilder(
            builder: (context, viewportConstraints) => Stack(
              children: [
                Column(
                  children: [
                    const _WorkspaceSyncLifecycleBridge(),
                    const _CalendarPreferencesBridge(),
                    const _HierarchyPreferencesBridge(),
                    _HierarchyPlanningModeBridge(
                      planningView: planningView,
                    ),
                    if (topAttentionNotice != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                        child: _WorkspaceAttentionCard(
                          notice: topAttentionNotice,
                          showBoardContext: multiBoardScope,
                          onPrimaryAction: () => _runWorkspaceNoticeAction(
                            context,
                            ref,
                            notice: topAttentionNotice,
                            action: topAttentionNotice.primaryAction,
                          ),
                          onSecondaryAction:
                              topAttentionNotice.secondaryAction == null
                                  ? null
                                  : () => _runWorkspaceNoticeAction(
                                        context,
                                        ref,
                                        notice: topAttentionNotice,
                                        action:
                                            topAttentionNotice.secondaryAction!,
                                      ),
                          onOpenCenter: () => topAttentionNotice.category ==
                                  WorkspaceAttentionNoticeCategory.reminder
                              ? _showReminderCenterSheet(
                                  context,
                                  ref,
                                  accentColorValuesByItemKey,
                                )
                              : _showSystemNotificationsSheet(context, ref),
                          onDismiss: !topAttentionNotice.dismissible
                              ? null
                              : () {
                                  if (topAttentionNotice.reminder != null) {
                                    ref
                                        .read(boardControllerProvider)
                                        .dismissReminderTopNotice(
                                          reminderId: topAttentionNotice
                                              .reminder!.reminderId,
                                        );
                                    return;
                                  }
                                  final systemNotice =
                                      topAttentionNotice.systemNotice;
                                  if (systemNotice == null) return;
                                  ref
                                      .read(boardControllerProvider)
                                      .dismissSystemNotice(
                                        noticeId: systemNotice.noticeId,
                                        stateToken: systemNotice.stateToken,
                                      );
                                },
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: searchExpanded
                          ? AppHelpTarget(
                              spec: _workspaceSearchHelpSpec(),
                              borderRadius: BorderRadius.circular(18),
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
                                        ref
                                            .read(
                                                boardTextQueryProvider.notifier)
                                            .state = value;
                                      },
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Collapse search',
                                    onPressed: () {
                                      ref
                                          .read(workspaceSearchExpandedProvider
                                              .notifier)
                                          .state = false;
                                    },
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                            )
                          : Builder(
                              builder: (context) {
                                final stripRow = TapRegion(
                                  groupId: boardItemFocusTapRegionGroup,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AppHelpTarget(
                                        spec: _workspaceCaptureHelpSpec(),
                                        borderRadius: BorderRadius.circular(20),
                                        child: Tooltip(
                                          message: 'Quick capture',
                                          child: FilledButton.tonalIcon(
                                            style: FilledButton.styleFrom(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 10,
                                              ),
                                            ),
                                            onPressed: canModifyItems
                                                ? () => _showQuickCaptureDialog(
                                                      context,
                                                      ref,
                                                    )
                                                : () => _showActionFeedback(
                                                      context,
                                                      'Current role cannot create items in this board.',
                                                    ),
                                            icon: const Icon(
                                                Icons.flash_on_outlined),
                                            label: const Text('Capture'),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      AppHelpTarget(
                                        spec: _workspaceBoardScopeHelpSpec(),
                                        borderRadius: BorderRadius.circular(20),
                                        child: Tooltip(
                                          message:
                                              'Board scope: ${_boardScopeLabel(boards, selectedBoardIds)}',
                                          child: InkWell(
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            onTap: () =>
                                                _showBoardSelectionSheet(
                                              context,
                                              ref,
                                              boards: boards,
                                              selectedBoardIds:
                                                  selectedBoardIds,
                                              currentBoardId: currentBoardId,
                                            ),
                                            child: Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .outlineVariant,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Badge(
                                                isLabelVisible: selectedBoardIds
                                                        .isNotEmpty &&
                                                    selectedBoardIds.length <
                                                        boards.length,
                                                label: Text(
                                                  '${selectedBoardIds.length}',
                                                ),
                                                child: const Icon(
                                                  Icons.view_list_outlined,
                                                  size: 18,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      AppHelpTarget(
                                        spec: _workspaceViewPickerHelpSpec(),
                                        borderRadius: BorderRadius.circular(20),
                                        child: Tooltip(
                                          message:
                                              'Workspace view: ${boardPlanningViewLabel(planningView)}',
                                          child: InkWell(
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            onTap: () =>
                                                _showWorkspaceViewPicker(
                                              context,
                                              ref,
                                              current: planningView,
                                            ),
                                            child: Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .outlineVariant,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Icon(
                                                boardPlanningViewIcon(
                                                    planningView),
                                                size: 18,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      AppHelpTarget(
                                        spec: _workspaceFiltersHelpSpec(),
                                        borderRadius: BorderRadius.circular(20),
                                        child: Tooltip(
                                          message: activeFilterCount > 0
                                              ? 'Filters ($activeFilterCount active)'
                                              : 'Filters',
                                          child: InkWell(
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            onTap: () =>
                                                _showWorkspaceFiltersSheet(
                                              context,
                                              ref,
                                              planningView: planningView,
                                              typeFilters: visibilityFilter,
                                              stateFilter: stateFilter,
                                              tagFilter: tagFilter,
                                              showOverdueOnly: showOverdueOnly,
                                              showDueSoonOnly: showDueSoonOnly,
                                              showArchivedOnly:
                                                  showArchivedOnly,
                                            ),
                                            child: Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .outlineVariant,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Badge(
                                                isLabelVisible:
                                                    activeFilterCount > 0,
                                                label:
                                                    Text('$activeFilterCount'),
                                                child: const Icon(
                                                  Icons.filter_list,
                                                  size: 18,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      AppHelpTarget(
                                        spec: _workspaceRemindersHelpSpec(),
                                        borderRadius: BorderRadius.circular(20),
                                        child: IconButton(
                                          tooltip: 'Reminders',
                                          onPressed: () =>
                                              _showReminderCenterSheet(
                                            context,
                                            ref,
                                            accentColorValuesByItemKey,
                                          ),
                                          icon: Badge(
                                            isLabelVisible: (remindersAsync
                                                        .valueOrNull?.length ??
                                                    0) >
                                                0,
                                            label: Text(
                                              '${remindersAsync.valueOrNull?.length ?? 0}',
                                            ),
                                            child: const Icon(
                                              Icons.notifications_none_outlined,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      AppHelpTarget(
                                        spec: _workspaceSearchHelpSpec(),
                                        borderRadius: BorderRadius.circular(20),
                                        child: IconButton(
                                          tooltip: 'Search items',
                                          onPressed: () {
                                            ref
                                                .read(
                                                  workspaceSearchExpandedProvider
                                                      .notifier,
                                                )
                                                .state = true;
                                          },
                                          icon: Badge(
                                            isLabelVisible:
                                                textQuery.trim().isNotEmpty,
                                            child: const Icon(Icons.search),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );

                                if (screenWidth < 760) {
                                  return SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: stripRow,
                                  );
                                }

                                return stripRow;
                              },
                            ),
                    ),
                    if (selectedItemIds.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Text(
                                '${selectedItemIds.length} selected',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const Spacer(),
                              PopupMenuButton<String>(
                                tooltip: 'Bulk actions',
                                onSelected: (value) {
                                  switch (value) {
                                    case 'bulk_move':
                                      if (bulkActionBoardId == null) {
                                        _showActionFeedback(
                                          context,
                                          'Bulk move works with items from one board at a time.',
                                        );
                                        return;
                                      }
                                      _showBulkMoveDialog(
                                        context,
                                        ref,
                                        columns: bulkActionColumns,
                                        selectedItemIds: selectedItemIds,
                                      );
                                      break;
                                    case 'bulk_archive':
                                      _confirmDestructiveAction(
                                        context,
                                        title: 'Archive selected items?',
                                        message:
                                            'Archive ${selectedItemIds.length} selected item(s)?',
                                        confirmLabel: 'Archive',
                                      ).then((confirmed) {
                                        if (!confirmed) return;
                                        _applyBulkUpdateAcrossBoards(
                                          context,
                                          ref,
                                          items: selectedItemsById.values,
                                          archived: true,
                                        );
                                      });
                                      break;
                                    case 'bulk_unarchive':
                                      _confirmDestructiveAction(
                                        context,
                                        title: 'Unarchive selected items?',
                                        message:
                                            'Unarchive ${selectedItemIds.length} selected item(s)?',
                                        confirmLabel: 'Unarchive',
                                      ).then((confirmed) {
                                        if (!confirmed) return;
                                        _applyBulkUpdateAcrossBoards(
                                          context,
                                          ref,
                                          items: selectedItemsById.values,
                                          archived: false,
                                        );
                                      });
                                      break;
                                    case 'bulk_add_tags':
                                      _showBulkTagDialog(
                                        context,
                                        ref,
                                        selectedItemIds: selectedItemIds,
                                        selectedItems: selectedItemsById.values,
                                        remove: false,
                                      );
                                      break;
                                    case 'bulk_remove_tags':
                                      _showBulkTagDialog(
                                        context,
                                        ref,
                                        selectedItemIds: selectedItemIds,
                                        selectedItems: selectedItemsById.values,
                                        remove: true,
                                      );
                                      break;
                                    case 'clear_selected':
                                      ref
                                          .read(
                                            selectedBoardItemIdsProvider
                                                .notifier,
                                          )
                                          .state = {};
                                      break;
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'bulk_move',
                                    child: Text('Bulk move selected'),
                                  ),
                                  PopupMenuItem(
                                    value: 'bulk_archive',
                                    child: Text('Archive selected'),
                                  ),
                                  PopupMenuItem(
                                    value: 'bulk_unarchive',
                                    child: Text('Unarchive selected'),
                                  ),
                                  PopupMenuItem(
                                    value: 'bulk_add_tags',
                                    child: Text('Add tags to selected'),
                                  ),
                                  PopupMenuItem(
                                    value: 'bulk_remove_tags',
                                    child: Text('Remove tags from selected'),
                                  ),
                                  PopupMenuDivider(),
                                  PopupMenuItem(
                                    value: 'clear_selected',
                                    child: Text('Clear selection'),
                                  ),
                                ],
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .secondaryContainer,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.checklist_outlined,
                                          size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Bulk actions',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (focusModeEnabled && focusedItemId != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.5),
                        child: Text(
                          'Focus mode: showing selected item context (ancestors + descendants)',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                    Expanded(
                      child: AppHelpTarget(
                        spec: _workspaceSurfaceHelpSpec(
                          planningView: planningView,
                          workspaceSurface: workspaceSurface,
                        ),
                        enabled: planningView != BoardPlanningView.calendar &&
                            planningView != BoardPlanningView.hierarchy,
                        borderRadius: BorderRadius.circular(24),
                        child: workspaceSurface == BoardWorkspaceSurface.inbox
                            ? (multiBoardScope
                                ? _buildMultiBoardInboxView(
                                    context: context,
                                    ref: ref,
                                    boardViews: boardViews,
                                    boards: boards,
                                    focusedItemId: focusedItemId,
                                    selectedItemIds: selectedItemIds,
                                    density: cardDensity,
                                    canModifyItems: canModifyItems,
                                    canManageBoard: canManageBoard,
                                    permissionProfilesByBoardId:
                                        permissionProfilesByBoardId,
                                  )
                                : _buildInboxView(
                                    context: context,
                                    ref: ref,
                                    allItems: snapshot.items,
                                    columns: columns,
                                    boards: boards,
                                    canModifyItems: canModifyItems,
                                    canManageBoard: canManageBoard,
                                    selectedItemIds: selectedItemIds,
                                    focusedItemId: focusedItemId,
                                    density: cardDensity,
                                    settings: snapshot.board.validationSettings,
                                  ))
                            : planningView == BoardPlanningView.calendar
                                ? BoardCalendarView(
                                    subview: calendarSubview,
                                    anchorDate: calendarAnchorDate,
                                    calendarSnapshot: calendarSnapshot,
                                    accentColorValuesByItemKey:
                                        accentColorValuesByItemKey,
                                    showUnscheduled: showCalendarUnscheduled,
                                    multiBoardScope: multiBoardScope,
                                    focusedItemId: focusedItemId,
                                    selectedItemIds: selectedItemIds,
                                    canModifyItemsByBoardId: {
                                      for (final entry
                                          in permissionProfilesByBoardId
                                              .entries)
                                        entry.key: entry.value.has(
                                          BoardCapability.modifyItems,
                                        ),
                                    },
                                    onAnchorDateChanged: (value) {
                                      ref
                                          .read(boardControllerProvider)
                                          .setCalendarAnchorDate(value);
                                    },
                                    onSubviewChanged: (value) {
                                      ref
                                          .read(boardControllerProvider)
                                          .setCalendarSubview(value);
                                    },
                                    onSelectItem: (item) {
                                      _focusItem(ref, item: item);
                                    },
                                    onOpenItemDetails: (item) {
                                      final boardItems =
                                          itemsByBoardId[item.boardId] ??
                                              snapshot.items;
                                      final boardColumns =
                                          columnsByBoardId[item.boardId] ??
                                              columns;
                                      final boardSettings =
                                          settingsByBoardId[item.boardId] ??
                                              snapshot.board.validationSettings;
                                      _showItemDetailsSheet(
                                        context,
                                        ref,
                                        item: item,
                                        allItems: boardItems,
                                        columns: boardColumns,
                                        settings: boardSettings,
                                      );
                                    },
                                    onMoveDueDate: (item, date) async {
                                      await _rescheduleItemDueDateWithUndo(
                                        context,
                                        ref,
                                        item: item,
                                        dueAt: date,
                                      );
                                    },
                                  )
                                : planningView == BoardPlanningView.kanban
                                    ? (multiBoardScope
                                        ? _buildMultiBoardKanbanView(
                                            context: context,
                                            ref: ref,
                                            boardViews: boardViews,
                                            filters: visibilityFilter,
                                            stateFilter: stateFilter,
                                            focusModeEnabled: focusModeEnabled,
                                            focusRelatedItemIds:
                                                focusRelatedItemIds,
                                            textQuery: textQuery,
                                            tagFilter: tagFilter,
                                            showOverdueOnly: showOverdueOnly,
                                            showDueSoonOnly: showDueSoonOnly,
                                            showArchivedOnly: showArchivedOnly,
                                            focusedItemId: focusedItemId,
                                            canModifyItems: canModifyItems,
                                            canManageBoard: canManageBoard,
                                            selectedItemIds: selectedItemIds,
                                            density: cardDensity,
                                            columnWidth: columnWidth,
                                            permissionProfilesByBoardId:
                                                permissionProfilesByBoardId,
                                          )
                                        : ListView(
                                            scrollDirection: Axis.horizontal,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8),
                                            children: [
                                              for (final column in columns)
                                                KeyedSubtree(
                                                  key: doingColumn != null &&
                                                          column.columnId ==
                                                              doingColumn
                                                                  .columnId
                                                      ? doingColumnAnchorKey
                                                      : null,
                                                  child: SizedBox(
                                                    width: columnWidth,
                                                    child: Padding(
                                                      padding:
                                                          EdgeInsets.symmetric(
                                                        vertical: compactDensity
                                                            ? 4
                                                            : 8,
                                                        horizontal:
                                                            compactDensity
                                                                ? 2
                                                                : 4,
                                                      ),
                                                      child: Card(
                                                        child: Padding(
                                                          padding:
                                                              EdgeInsets.all(
                                                                  compactDensity
                                                                      ? 8
                                                                      : 12),
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Row(
                                                                children: [
                                                                  Expanded(
                                                                    child:
                                                                        Tooltip(
                                                                      message:
                                                                          column
                                                                              .name,
                                                                      child:
                                                                          Text(
                                                                        column
                                                                            .name,
                                                                        maxLines: compactDensity
                                                                            ? 2
                                                                            : 3,
                                                                        overflow:
                                                                            TextOverflow.ellipsis,
                                                                        style: compactDensity
                                                                            ? Theme.of(context).textTheme.titleSmall
                                                                            : Theme.of(context).textTheme.titleMedium,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  IconButton(
                                                                    tooltip:
                                                                        'Move left',
                                                                    onPressed:
                                                                        !canManageBoard
                                                                            ? null
                                                                            : () {
                                                                                final index = columns.indexWhere((c) => c.columnId == column.columnId);
                                                                                if (index <= 0) {
                                                                                  return;
                                                                                }
                                                                                final ordered = [
                                                                                  for (final c in columns) c.columnId
                                                                                ];
                                                                                final id = ordered.removeAt(index);
                                                                                ordered.insert(index - 1, id);
                                                                                _runGuardedAction(
                                                                                  context,
                                                                                  () => ref.read(boardControllerProvider).reorderColumns(ordered),
                                                                                );
                                                                              },
                                                                    icon: Text(
                                                                      '<',
                                                                      style: Theme.of(
                                                                              context)
                                                                          .textTheme
                                                                          .titleMedium
                                                                          ?.copyWith(
                                                                            fontWeight:
                                                                                FontWeight.w700,
                                                                          ),
                                                                    ),
                                                                  ),
                                                                  IconButton(
                                                                    tooltip:
                                                                        'Move right',
                                                                    onPressed:
                                                                        !canManageBoard
                                                                            ? null
                                                                            : () {
                                                                                final index = columns.indexWhere((c) => c.columnId == column.columnId);
                                                                                if (index < 0 || index >= columns.length - 1) {
                                                                                  return;
                                                                                }
                                                                                final ordered = [
                                                                                  for (final c in columns) c.columnId
                                                                                ];
                                                                                final id = ordered.removeAt(index);
                                                                                ordered.insert(index + 1, id);
                                                                                _runGuardedAction(
                                                                                  context,
                                                                                  () => ref.read(boardControllerProvider).reorderColumns(ordered),
                                                                                );
                                                                              },
                                                                    icon: Text(
                                                                      '>',
                                                                      style: Theme.of(
                                                                              context)
                                                                          .textTheme
                                                                          .titleMedium
                                                                          ?.copyWith(
                                                                            fontWeight:
                                                                                FontWeight.w700,
                                                                          ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                              const SizedBox(
                                                                  height: 8),
                                                              Builder(
                                                                builder: (_) {
                                                                  final visibleItems =
                                                                      visibleItemsByColumn[
                                                                              column.columnId] ??
                                                                          const <WorkItem>[];

                                                                  return Padding(
                                                                    padding: const EdgeInsets
                                                                        .only(
                                                                        bottom:
                                                                            6),
                                                                    child: Text(
                                                                      '${visibleItems.length} item(s)',
                                                                      style: Theme.of(
                                                                              context)
                                                                          .textTheme
                                                                          .labelMedium,
                                                                    ),
                                                                  );
                                                                },
                                                              ),
                                                              Expanded(
                                                                child: DragTarget<
                                                                    WorkItem>(
                                                                  onWillAcceptWithDetails:
                                                                      (details) {
                                                                    final tileItems =
                                                                        visibleItemsByColumn[column.columnId] ??
                                                                            const <WorkItem>[];
                                                                    if (tileItems
                                                                        .isNotEmpty) {
                                                                      return false;
                                                                    }
                                                                    return details
                                                                            .data
                                                                            .columnId !=
                                                                        column
                                                                            .columnId;
                                                                  },
                                                                  onAcceptWithDetails:
                                                                      (details) {
                                                                    final movedItem =
                                                                        details
                                                                            .data;
                                                                    if (movedItem
                                                                            .columnId ==
                                                                        column
                                                                            .columnId) {
                                                                      return;
                                                                    }
                                                                    if (!canModifyItems) {
                                                                      _showActionFeedback(
                                                                        context,
                                                                        'Current role cannot modify items in this board.',
                                                                      );
                                                                      return;
                                                                    }
                                                                    _moveItemWithUndo(
                                                                      context,
                                                                      ref,
                                                                      item:
                                                                          movedItem,
                                                                      toColumnId:
                                                                          column
                                                                              .columnId,
                                                                    );
                                                                  },
                                                                  builder: (context,
                                                                      candidateData,
                                                                      rejectedData) {
                                                                    final tileItems =
                                                                        visibleItemsByColumn[column.columnId] ??
                                                                            const <WorkItem>[];
                                                                    final isDropActive =
                                                                        candidateData
                                                                            .any(
                                                                      (item) =>
                                                                          item !=
                                                                              null &&
                                                                          item.columnId !=
                                                                              column.columnId,
                                                                    );

                                                                    return AnimatedContainer(
                                                                      duration: const Duration(
                                                                          milliseconds:
                                                                              120),
                                                                      decoration:
                                                                          BoxDecoration(
                                                                        color: isDropActive
                                                                            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35)
                                                                            : Colors.transparent,
                                                                        borderRadius:
                                                                            BorderRadius.circular(8),
                                                                        border:
                                                                            Border.all(
                                                                          color: isDropActive
                                                                              ? Theme.of(context).colorScheme.primary
                                                                              : Colors.transparent,
                                                                        ),
                                                                      ),
                                                                      child:
                                                                          ListView(
                                                                        padding:
                                                                            EdgeInsets.all(
                                                                          compactDensity
                                                                              ? 2
                                                                              : 4,
                                                                        ),
                                                                        children: [
                                                                          if (tileItems
                                                                              .isNotEmpty)
                                                                            _buildReorderGapTarget(
                                                                              context,
                                                                              ref,
                                                                              enabled: canModifyItems,
                                                                              boardId: snapshot.board.boardId,
                                                                              beforeItemId: null,
                                                                              afterItemId: tileItems.first.itemId,
                                                                              toColumnId: column.columnId,
                                                                              thickness: 8,
                                                                              margin: const EdgeInsets.only(
                                                                                bottom: 2,
                                                                              ),
                                                                            ),
                                                                          for (var index = 0;
                                                                              index < tileItems.length;
                                                                              index++) ...[
                                                                            (() {
                                                                              final item = tileItems[index];
                                                                              return BoardItemTile(
                                                                                item: item,
                                                                                columns: columns,
                                                                                allItems: snapshot.items,
                                                                                density: cardDensity,
                                                                                parentPathMode: snapshot.board.validationSettings.hierarchyParentPathMode,
                                                                                focused: focusedItemId == item.itemId,
                                                                                selected: selectedItemIds.contains(item.itemId),
                                                                                childCount: snapshot.items.where((x) => x.parentId == item.itemId).length,
                                                                                onSelect: () {
                                                                                  _focusItem(
                                                                                    ref,
                                                                                    item: item,
                                                                                  );
                                                                                },
                                                                                onAddChildAction: () {
                                                                                  _showSmartChildCreateDialog(
                                                                                    context,
                                                                                    ref,
                                                                                    parent: item,
                                                                                    canManageBoard: canManageBoard,
                                                                                  );
                                                                                },
                                                                                onEdit: () {
                                                                                  _showEditItemSheet(
                                                                                    context,
                                                                                    ref,
                                                                                    item: item,
                                                                                    allItems: snapshot.items,
                                                                                    settings: snapshot.board.validationSettings,
                                                                                  );
                                                                                },
                                                                                onViewDetails: () {
                                                                                  _showItemDetailsSheet(
                                                                                    context,
                                                                                    ref,
                                                                                    item: item,
                                                                                    allItems: snapshot.items,
                                                                                    columns: snapshot.columns,
                                                                                    settings: snapshot.board.validationSettings,
                                                                                  );
                                                                                },
                                                                                onToggleArchive: () {
                                                                                  _toggleArchiveWithUndo(
                                                                                    context,
                                                                                    ref,
                                                                                    item: item,
                                                                                  );
                                                                                },
                                                                                onMoveToColumn: (toColumnId) => _moveItemWithUndo(
                                                                                  context,
                                                                                  ref,
                                                                                  item: item,
                                                                                  toColumnId: toColumnId,
                                                                                ),
                                                                                onToggleSelected: () => _toggleItemSelection(
                                                                                  ref,
                                                                                  item.itemId,
                                                                                ),
                                                                                onReparent: canModifyItems
                                                                                    ? () => _showReparentDialog(
                                                                                          context,
                                                                                          ref,
                                                                                          item: item,
                                                                                          allItems: snapshot.items,
                                                                                        )
                                                                                    : null,
                                                                                onJumpToParent: item.parentId == null
                                                                                    ? null
                                                                                    : () {
                                                                                        ref.read(boardVisibilityFilterProvider.notifier).state = <WorkItemType>{};
                                                                                        _setFocusedItemId(
                                                                                          ref,
                                                                                          item.parentId,
                                                                                          hierarchyItemKey: item.parentId == null
                                                                                              ? null
                                                                                              : _hierarchyNodeKey(
                                                                                                  boardId: item.boardId,
                                                                                                  itemId: item.parentId!,
                                                                                                ),
                                                                                        );
                                                                                        ref.read(focusModeEnabledProvider.notifier).state = true;
                                                                                      },
                                                                                onDelete: canModifyItems
                                                                                    ? () => _deleteItemWithUndo(
                                                                                          context,
                                                                                          ref,
                                                                                          item: item,
                                                                                          allItems: snapshot.items,
                                                                                        )
                                                                                    : null,
                                                                                canModifyItems: canModifyItems,
                                                                                accentColor: !hierarchyColorEnabled
                                                                                    ? null
                                                                                    : (() {
                                                                                        final topGoalId = topLevelGoalIdForItem(
                                                                                          item,
                                                                                          allItemsById,
                                                                                        );
                                                                                        final accentColorValue = topGoalId == null ? null : goalColors[topGoalId];
                                                                                        return accentColorValue == null ? null : Color(accentColorValue);
                                                                                      })(),
                                                                              );
                                                                            })(),
                                                                            _buildReorderGapTarget(
                                                                              context,
                                                                              ref,
                                                                              enabled: canModifyItems,
                                                                              boardId: snapshot.board.boardId,
                                                                              beforeItemId: tileItems[index].itemId,
                                                                              afterItemId: index + 1 < tileItems.length ? tileItems[index + 1].itemId : null,
                                                                              toColumnId: column.columnId,
                                                                              thickness: 8,
                                                                              margin: const EdgeInsets.only(
                                                                                bottom: 2,
                                                                              ),
                                                                            ),
                                                                          ],
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
                                                ),
                                            ],
                                          ))
                                    : _buildAlternativeView(
                                        context: context,
                                        ref: ref,
                                        planningView: planningView,
                                        columns: multiBoardScope
                                            ? mergedColumns
                                            : columns,
                                        allItems: multiBoardScope
                                            ? mergedItems
                                            : snapshot.items,
                                        filters: visibilityFilter,
                                        stateFilter: stateFilter,
                                        focusModeEnabled: focusModeEnabled,
                                        focusRelatedItemIds:
                                            focusRelatedItemIds,
                                        textQuery: textQuery,
                                        tagFilter: tagFilter,
                                        columnsById: multiBoardScope
                                            ? mergedColumnsById
                                            : columnsById,
                                        showOverdueOnly: showOverdueOnly,
                                        showDueSoonOnly: showDueSoonOnly,
                                        showArchivedOnly: showArchivedOnly,
                                        focusedItemId: focusedItemId,
                                        selectedHierarchyItemId:
                                            selectedHierarchyItemId,
                                        canModifyItems: canModifyItems,
                                        canManageBoard: canManageBoard,
                                        collapsedHierarchyItemIds:
                                            collapsedHierarchyItemIds,
                                        selectedItemIds: selectedItemIds,
                                        density: cardDensity,
                                        settings:
                                            snapshot.board.validationSettings,
                                        columnsByBoardId: multiBoardScope
                                            ? columnsByBoardId
                                            : null,
                                        itemsByBoardId: multiBoardScope
                                            ? itemsByBoardId
                                            : null,
                                        settingsByBoardId: multiBoardScope
                                            ? settingsByBoardId
                                            : null,
                                        permissionProfilesByBoardId:
                                            multiBoardScope
                                                ? permissionProfilesByBoardId
                                                : null,
                                      ),
                      ),
                    ),
                  ],
                ),
                if (activeDraggedItem != null && dragOverlayColumns != null)
                  _buildNearFingerColumnMoveOverlay(
                    context,
                    ref,
                    draggedItem: activeDraggedItem,
                    boardColumns: dragOverlayColumns,
                    canModifyItems: dragOverlayCanModifyItems,
                    viewportHeight: viewportConstraints.maxHeight,
                  ),
                if (feedbackQueue.isNotEmpty)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: pendingUndoOperation != null ? 172 : 88,
                    child: _WorkspaceFeedbackBar(
                      message: feedbackQueue.first,
                    ),
                  ),
                if (pendingUndoOperation != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 88,
                    child: _PendingUndoBar(
                      operation: pendingUndoOperation,
                    ),
                  ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _WorkspaceAttentionCard extends StatelessWidget {
  const _WorkspaceAttentionCard({
    required this.notice,
    required this.showBoardContext,
    required this.onPrimaryAction,
    required this.onOpenCenter,
    this.onSecondaryAction,
    this.onDismiss,
  });

  final WorkspaceAttentionNotice notice;
  final bool showBoardContext;
  final VoidCallback onPrimaryAction;
  final VoidCallback onOpenCenter;
  final VoidCallback? onSecondaryAction;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message =
        showBoardContext && notice.reminder?.boardName.isNotEmpty == true
            ? '${notice.reminder!.boardName} • ${notice.message}'
            : notice.message;
    final icon = switch (notice.category) {
      WorkspaceAttentionNoticeCategory.access => Icons.lock_outline,
      WorkspaceAttentionNoticeCategory.sync => Icons.sync_problem,
      WorkspaceAttentionNoticeCategory.reminder =>
        notice.reminder?.isOverdue == true
            ? Icons.warning_amber_rounded
            : Icons.notifications_active_outlined,
    };
    final accentColor = switch (notice.severity) {
      WorkspaceAttentionSeverity.critical => theme.colorScheme.error,
      WorkspaceAttentionSeverity.warning => theme.colorScheme.primary,
      WorkspaceAttentionSeverity.neutral => theme.colorScheme.primary,
    };

    return Material(
      key: const ValueKey('workspace-attention-card'),
      elevation: 1,
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accentColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notice.title,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: onPrimaryAction,
                        child: Text(notice.primaryAction.label),
                      ),
                      if (notice.secondaryAction != null &&
                          onSecondaryAction != null)
                        TextButton(
                          onPressed: onSecondaryAction,
                          child: Text(notice.secondaryAction!.label),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  tooltip: notice.category ==
                          WorkspaceAttentionNoticeCategory.reminder
                      ? 'Open reminders'
                      : 'Open notifications',
                  onPressed: onOpenCenter,
                  icon: const Icon(Icons.chevron_right),
                ),
                if (onDismiss != null)
                  IconButton(
                    tooltip: 'Dismiss',
                    onPressed: onDismiss,
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceSyncLifecycleBridge extends ConsumerStatefulWidget {
  const _WorkspaceSyncLifecycleBridge();

  @override
  ConsumerState<_WorkspaceSyncLifecycleBridge> createState() =>
      _WorkspaceSyncLifecycleBridgeState();
}

class _WorkspaceBoardViewData {
  const _WorkspaceBoardViewData({
    required this.board,
    required this.snapshot,
    required this.isActiveBoard,
  });

  final Board board;
  final BoardSnapshot snapshot;
  final bool isActiveBoard;
}

class _MergedKanbanLaneData {
  const _MergedKanbanLaneData({
    required this.key,
    required this.displayColumn,
    required this.columnsByBoardId,
    required this.orderIndex,
  });

  final String key;
  final BoardColumn displayColumn;
  final Map<String, BoardColumn> columnsByBoardId;
  final int orderIndex;
}

class _WorkspaceFeedbackBar extends ConsumerStatefulWidget {
  const _WorkspaceFeedbackBar({
    required this.message,
  });

  final WorkspaceFeedbackMessage message;

  @override
  ConsumerState<_WorkspaceFeedbackBar> createState() =>
      _WorkspaceFeedbackBarState();
}

class _WorkspaceFeedbackBarState extends ConsumerState<_WorkspaceFeedbackBar> {
  Timer? _dismissTimer;

  Duration get _remaining {
    final remaining = widget.message.expiresAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  void initState() {
    super.initState();
    _scheduleDismiss();
  }

  @override
  void didUpdateWidget(covariant _WorkspaceFeedbackBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.feedbackId != widget.message.feedbackId) {
      _scheduleDismiss();
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  void _scheduleDismiss() {
    _dismissTimer?.cancel();
    final remaining = _remaining;
    if (remaining == Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(boardControllerProvider).dismissWorkspaceFeedback(
              widget.message.feedbackId,
            );
      });
      return;
    }
    _dismissTimer = Timer(remaining, () {
      if (!mounted) return;
      ref.read(boardControllerProvider).dismissWorkspaceFeedback(
            widget.message.feedbackId,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = switch (widget.message.severity) {
      WorkspaceFeedbackSeverity.info => Icons.info_outline,
      WorkspaceFeedbackSeverity.success => Icons.check_circle_outline,
      WorkspaceFeedbackSeverity.error => Icons.error_outline,
    };
    final accentColor = switch (widget.message.severity) {
      WorkspaceFeedbackSeverity.info => theme.colorScheme.primary,
      WorkspaceFeedbackSeverity.success => const Color(0xFF1C8B5A),
      WorkspaceFeedbackSeverity.error => theme.colorScheme.error,
    };

    return SafeArea(
      top: false,
      child: Material(
        key: const ValueKey('workspace-feedback-bar'),
        elevation: 8,
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Icon(icon, color: accentColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.message.message,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              IconButton(
                tooltip: 'Dismiss feedback',
                onPressed: () {
                  ref.read(boardControllerProvider).dismissWorkspaceFeedback(
                        widget.message.feedbackId,
                      );
                },
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingUndoBar extends ConsumerStatefulWidget {
  const _PendingUndoBar({
    required this.operation,
  });

  final BoardUndoOperation operation;

  @override
  ConsumerState<_PendingUndoBar> createState() => _PendingUndoBarState();
}

class _PendingUndoBarState extends ConsumerState<_PendingUndoBar> {
  Timer? _dismissTimer;

  Duration get _remaining {
    final remaining = widget.operation.expiresAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  void initState() {
    super.initState();
    _scheduleDismiss();
  }

  @override
  void didUpdateWidget(covariant _PendingUndoBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.operation.operationId != widget.operation.operationId) {
      _scheduleDismiss();
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  void _scheduleDismiss() {
    _dismissTimer?.cancel();
    final remaining = _remaining;
    if (remaining == Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(boardControllerProvider).clearPendingUndo(
              operationId: widget.operation.operationId,
            );
      });
      return;
    }
    _dismissTimer = Timer(remaining, () {
      if (!mounted) return;
      ref.read(boardControllerProvider).clearPendingUndo(
            operationId: widget.operation.operationId,
          );
    });
  }

  Future<void> _undo() async {
    final restored =
        await ref.read(boardControllerProvider).undoPendingOperation();
    if (!mounted || restored) return;
  }

  void _dismiss() {
    ref.read(boardControllerProvider).clearPendingUndo(
          operationId: widget.operation.operationId,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = _remaining;
    final progressDuration = remaining == Duration.zero
        ? const Duration(milliseconds: 1)
        : remaining;

    return SafeArea(
      top: false,
      child: Material(
        key: const ValueKey('pending-undo-bar'),
        elevation: 8,
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: TweenAnimationBuilder<double>(
            key: ValueKey(widget.operation.operationId),
            tween: Tween<double>(begin: 1, end: 0),
            duration: progressDuration,
            curve: Curves.linear,
            builder: (context, value, child) {
              final secondsLeft = max(
                0,
                (progressDuration.inMilliseconds * value / 1000).ceil(),
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.undo_outlined, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.operation.message,
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                secondsLeft > 0
                                    ? 'Undo available for ${secondsLeft}s'
                                    : 'Undo expiring',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _undo,
                          child: const Text('Undo'),
                        ),
                        IconButton(
                          key: const ValueKey('pending-undo-dismiss-button'),
                          tooltip: 'Dismiss undo',
                          onPressed: _dismiss,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  LinearProgressIndicator(
                    minHeight: 3,
                    value: value.clamp(0, 1),
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _WorkspaceSyncLifecycleBridgeState
    extends ConsumerState<_WorkspaceSyncLifecycleBridge>
    with WidgetsBindingObserver {
  bool _syncInFlight = false;
  bool _syncRequestedWhileInFlight = false;
  bool _forceRequestedWhileInFlight = false;
  late final SyncRetryScheduler _retryScheduler;
  ProviderSubscription<DateTime?>? _retryScheduleListener;

  @override
  void initState() {
    super.initState();
    _retryScheduler = SyncRetryScheduler(
      onRetry: () => _triggerAutoSync(force: false),
    );
    _retryScheduleListener = ref.listenManual<DateTime?>(
      outboxStatusProvider.select(
        (value) => value.valueOrNull?.nextRetryAt,
      ),
      (previous, next) {
        if (!useFirebaseSync) {
          _retryScheduler.cancel();
          return;
        }
        _retryScheduler.schedule(next);
      },
      fireImmediately: true,
    );
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerAutoSync(force: false);
    });
  }

  @override
  void dispose() {
    _retryScheduleListener?.close();
    _retryScheduler.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _triggerAutoSync(force: true);
    }
  }

  Future<void> _triggerAutoSync({required bool force}) async {
    if (!mounted || !useFirebaseSync) return;
    if (_syncInFlight) {
      _syncRequestedWhileInFlight = true;
      _forceRequestedWhileInFlight |= force;
      return;
    }

    _syncInFlight = true;
    try {
      final pendingCount = await ref.read(pendingOutboxCountProvider.future);
      if (pendingCount <= 0) return;
      await ref.read(boardControllerProvider).syncNow(
            ignoreRetrySchedule: force,
          );
    } catch (_) {
      // Best-effort background sync; UI shows latest sync status.
    } finally {
      _syncInFlight = false;
      if (_syncRequestedWhileInFlight && mounted) {
        final forceNext = _forceRequestedWhileInFlight;
        _syncRequestedWhileInFlight = false;
        _forceRequestedWhileInFlight = false;
        unawaited(_triggerAutoSync(force: forceNext));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int?>(
      pendingOutboxCountProvider.select((value) => value.valueOrNull),
      (previous, next) {
        if (!useFirebaseSync) return;
        final nextCount = next ?? 0;
        final previousCount = previous ?? 0;
        if (nextCount > 0 && nextCount > previousCount) {
          _triggerAutoSync(force: false);
        }
      },
    );
    return const SizedBox.shrink();
  }
}

class _CalendarPreferencesBridge extends ConsumerStatefulWidget {
  const _CalendarPreferencesBridge();

  @override
  ConsumerState<_CalendarPreferencesBridge> createState() =>
      _CalendarPreferencesBridgeState();
}

class _CalendarPreferencesBridgeState
    extends ConsumerState<_CalendarPreferencesBridge> {
  String? _lastAppliedUserId;

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(boardScopeUserIdProvider);
    final preferencesAsync = ref.watch(boardCalendarPreferencesProvider);
    final preferences = preferencesAsync.valueOrNull;
    if (preferences == null) {
      return const SizedBox.shrink();
    }
    final shouldApply = _lastAppliedUserId != userId;

    if (shouldApply) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(boardCalendarSubviewProvider.notifier).state =
            preferences.lastSubview;
        ref.read(boardCalendarVisibleDateKindsProvider.notifier).state =
            preferences.visibleDateKinds;
        ref.read(boardCalendarShowUnscheduledProvider.notifier).state =
            preferences.showUnscheduled;
        _lastAppliedUserId = userId;
      });
    }

    return const SizedBox.shrink();
  }
}

class _HierarchyPreferencesBridge extends ConsumerStatefulWidget {
  const _HierarchyPreferencesBridge();

  @override
  ConsumerState<_HierarchyPreferencesBridge> createState() =>
      _HierarchyPreferencesBridgeState();
}

class _HierarchyPreferencesBridgeState
    extends ConsumerState<_HierarchyPreferencesBridge> {
  String? _lastAppliedUserId;
  bool _applyScheduled = false;

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(boardScopeUserIdProvider);
    final collapsedItemIds =
        ref.watch(hierarchyCollapsedItemIdsPreferencesProvider).valueOrNull;
    if (collapsedItemIds == null ||
        _lastAppliedUserId == userId ||
        _applyScheduled) {
      return const SizedBox.shrink();
    }

    _applyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(boardScopeUserIdProvider) != userId) {
        _applyScheduled = false;
        return;
      }
      ref.read(collapsedHierarchyItemIdsProvider.notifier).state =
          Set<String>.unmodifiable(collapsedItemIds);
      _lastAppliedUserId = userId;
      _applyScheduled = false;
    });
    return const SizedBox.shrink();
  }
}

class _HierarchyPlanningModeBridge extends ConsumerStatefulWidget {
  const _HierarchyPlanningModeBridge({
    required this.planningView,
  });

  final BoardPlanningView planningView;

  @override
  ConsumerState<_HierarchyPlanningModeBridge> createState() =>
      _HierarchyPlanningModeBridgeState();
}

class _HierarchyPlanningModeBridgeState
    extends ConsumerState<_HierarchyPlanningModeBridge> {
  bool _appliedForCurrentEntry = false;

  @override
  void initState() {
    super.initState();
    _scheduleResetIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _HierarchyPlanningModeBridge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.planningView != widget.planningView) {
      _scheduleResetIfNeeded();
    }
  }

  void _scheduleResetIfNeeded() {
    if (widget.planningView != BoardPlanningView.hierarchy) {
      _appliedForCurrentEntry = false;
      return;
    }
    if (_appliedForCurrentEntry) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(boardControllerProvider).setPlanningView(
            BoardPlanningView.hierarchy,
          );
      _appliedForCurrentEntry = true;
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _HierarchyGuidePainter extends CustomPainter {
  const _HierarchyGuidePainter({
    required this.depth,
    required this.color,
  });

  final int depth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (depth <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < depth; i++) {
      final x = (i * 10.0) + 5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    final connectorStartX = ((depth - 1) * 10.0) + 5;
    final connectorEndX = size.width;
    final midY = size.height * 0.5;
    canvas.drawLine(
        Offset(connectorStartX, midY), Offset(connectorEndX, midY), paint);
  }

  @override
  bool shouldRepaint(covariant _HierarchyGuidePainter oldDelegate) {
    return oldDelegate.depth != depth || oldDelegate.color != color;
  }
}
