import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/board_validation_settings.dart';
import '../domain/models/column.dart';
import '../domain/models/work_item.dart';
import '../domain/models/work_item_activity_event.dart';
import '../domain/models/work_item_recurrence.dart';
import '../domain/models/work_item_type.dart';
import '../domain/policies/board_permissions.dart';
import 'board_controller.dart';

Future<void> showBoardItemDetailsSheet(
  BuildContext context,
  WidgetRef ref, {
  required WorkItem item,
  required List<WorkItem> allItems,
  required List<BoardColumn> columns,
  required BoardValidationSettings settings,
  Future<void> Function(
    WorkItem currentItem,
    List<WorkItem> liveItems,
    BoardValidationSettings liveSettings,
  )? onEdit,
  Future<void> Function(WorkItem item, String toColumnId)? onMoveToColumn,
}) async {
  final timelineFuture = ref
      .read(workItemActivityRepositoryProvider)
      .listForItem(boardId: item.boardId, itemId: item.itemId);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Consumer(
      builder: (context, bottomSheetRef, _) {
        final liveSnapshot = bottomSheetRef
            .watch(boardSnapshotProvider(item.boardId))
            .valueOrNull;
        final liveItems = liveSnapshot?.items ?? allItems;
        final liveSettings = liveSnapshot?.board.validationSettings ?? settings;
        final currentItem = liveItems
            .where((entry) => entry.itemId == item.itemId)
            .cast<WorkItem>()
            .firstWhere((_) => true, orElse: () => item);
        final boardColumns = [...(liveSnapshot?.columns ?? columns)]
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
        final parent = currentItem.parentId == null
            ? null
            : liveItems
                .where((entry) => entry.itemId == currentItem.parentId)
                .cast<WorkItem?>()
                .firstWhere((_) => true, orElse: () => null);
        final column = boardColumns
            .where((entry) => entry.columnId == currentItem.columnId)
            .cast<BoardColumn?>()
            .firstWhere((_) => true, orElse: () => null);
        final description = currentItem.description?.trim();
        final hasDescription = description != null && description.isNotEmpty;
        final isOverdue = _isItemOverdue(currentItem);
        final scopeUserId = bottomSheetRef.watch(boardScopeUserIdProvider);
        final boardPermissionProfile = liveSnapshot == null
            ? null
            : BoardPermissions.profileFor(
                snapshot: liveSnapshot,
                userId: scopeUserId,
              );
        final canModifyStatus =
            (boardPermissionProfile?.has(BoardCapability.modifyItems) ??
                    false) &&
                boardColumns.length > 1 &&
                onMoveToColumn != null;

        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.58,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ListView(
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      currentItem.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    if (parent != null) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            Icons.subdirectory_arrow_right,
                                            size: 16,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              parent.title,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (onEdit != null) ...[
                                const SizedBox(width: 12),
                                FilledButton.tonalIcon(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    onEdit(
                                      currentItem,
                                      liveItems,
                                      liveSettings,
                                    );
                                  },
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Edit'),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(label: Text(_typeLabel(currentItem.type))),
                              if (currentItem.completedAt != null)
                                const Chip(label: Text('Done')),
                              if (currentItem.archived)
                                const Chip(label: Text('Archived')),
                              if (currentItem.isInbox)
                                const Chip(label: Text('Inbox')),
                              if (isOverdue)
                                Chip(
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .errorContainer,
                                  label: Text(
                                    'Overdue',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onErrorContainer,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Status',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 8),
                          if (column == null || boardColumns.length <= 1)
                            Chip(label: Text(column?.name ?? 'Unknown status'))
                          else
                            SingleChildScrollView(
                              key: const ValueKey('item-details-status-row'),
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final statusColumn in boardColumns)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        key: ValueKey(
                                          'item-status-chip-${statusColumn.columnId}',
                                        ),
                                        label: Text(statusColumn.name),
                                        selected: statusColumn.columnId ==
                                            currentItem.columnId,
                                        onSelected: !canModifyStatus ||
                                                statusColumn.columnId ==
                                                    currentItem.columnId
                                            ? null
                                            : (_) {
                                                onMoveToColumn(
                                                  currentItem,
                                                  statusColumn.columnId,
                                                );
                                              },
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildDetailsSectionCard(
                    context,
                    title: 'Quick facts',
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (liveSettings.showDueDate &&
                            currentItem.dueAt != null)
                          _buildDetailsFactTile(
                            context,
                            icon: Icons.event_outlined,
                            label: 'Due',
                            value: _formatDetailsDate(
                              context,
                              currentItem.dueAt!.toLocal(),
                            ),
                            hint: _relativeDateHint(
                              currentItem.dueAt!,
                              overdue: isOverdue,
                            ),
                            emphasized: isOverdue,
                          ),
                        if (liveSettings.showStartDate &&
                            currentItem.startAt != null)
                          _buildDetailsFactTile(
                            context,
                            icon: Icons.play_circle_outline,
                            label: 'Start',
                            value: _formatDetailsDate(
                              context,
                              currentItem.startAt!.toLocal(),
                            ),
                            hint: _relativeDateHint(currentItem.startAt!),
                          ),
                        if (liveSettings.showTargetEndDate &&
                            currentItem.targetEndAt != null)
                          _buildDetailsFactTile(
                            context,
                            icon: Icons.flag_outlined,
                            label: 'Target end',
                            value: _formatDetailsDate(
                              context,
                              currentItem.targetEndAt!.toLocal(),
                            ),
                            hint: _relativeDateHint(currentItem.targetEndAt!),
                          ),
                        if (liveSettings.showEstimatedEffort &&
                            currentItem.estimatedEffortMinutes != null)
                          _buildDetailsFactTile(
                            context,
                            icon: Icons.timer_outlined,
                            label: 'Estimate',
                            value: _minutesLabel(
                              currentItem.estimatedEffortMinutes!,
                            ),
                          ),
                        if (liveSettings.showActualEffort &&
                            currentItem.actualEffortMinutes != null)
                          _buildDetailsFactTile(
                            context,
                            icon: Icons.hourglass_bottom_outlined,
                            label: 'Actual',
                            value: _minutesLabel(
                              currentItem.actualEffortMinutes!,
                            ),
                          ),
                        _buildDetailsFactTile(
                          context,
                          icon: Icons.update_outlined,
                          label: 'Updated',
                          value: _formatDetailsDate(
                            context,
                            currentItem.updatedAt.toLocal(),
                          ),
                          hint: _formatDetailsDateTime(
                            context,
                            currentItem.updatedAt.toLocal(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasDescription) ...[
                    const SizedBox(height: 12),
                    _buildDetailsSectionCard(
                      context,
                      title: 'Description',
                      child: Text(
                        description,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(height: 1.4),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _buildDetailsSectionCard(
                    context,
                    title: 'Context',
                    child: Column(
                      children: [
                        if (parent != null)
                          _buildDetailsFieldRow(
                            context,
                            label: 'Parent',
                            value: parent.title,
                            icon: Icons.subdirectory_arrow_right,
                          ),
                        _buildDetailsFieldRow(
                          context,
                          label: 'Path',
                          value: _hierarchyPath(
                            item: currentItem,
                            allItems: liveItems,
                          ),
                          icon: Icons.account_tree_outlined,
                        ),
                        if (column != null)
                          _buildDetailsFieldRow(
                            context,
                            label: 'Column',
                            value: column.name,
                            icon: Icons.view_kanban_outlined,
                          ),
                        if (currentItem.tags.isNotEmpty)
                          _buildDetailsFieldRow(
                            context,
                            label: 'Tags',
                            value: currentItem.tags.join(', '),
                            icon: Icons.sell_outlined,
                          ),
                        if (currentItem.recurrence != null &&
                            currentItem.recurrence!.enabled)
                          _buildDetailsFieldRow(
                            context,
                            label: 'Recurs',
                            value: _recurrenceSummary(currentItem.recurrence!),
                            icon: Icons.repeat_outlined,
                          ),
                        if (liveSettings.showCreatedDate)
                          _buildDetailsFieldRow(
                            context,
                            label: 'Created',
                            value: _formatDetailsDateTime(
                              context,
                              currentItem.createdAt.toLocal(),
                            ),
                            icon: Icons.schedule_outlined,
                          ),
                        if (liveSettings.showCompletedDate &&
                            currentItem.completedAt != null)
                          _buildDetailsFieldRow(
                            context,
                            label: 'Completed',
                            value: _formatDetailsDateTime(
                              context,
                              currentItem.completedAt!.toLocal(),
                            ),
                            icon: Icons.task_alt_outlined,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildDetailsSectionCard(
                    context,
                    title: 'Activity',
                    subtitle: 'Recent changes for this item',
                    child: FutureBuilder<List<WorkItemActivityEvent>>(
                      future: timelineFuture,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        final events = snapshot.data!;
                        if (events.isEmpty) {
                          return const Text('No activity yet for this item.');
                        }
                        return Column(
                          children: [
                            for (var i = 0; i < events.length; i++) ...[
                              if (i > 0) const Divider(height: 16),
                              _buildActivityRow(
                                context,
                                event: events[i],
                              ),
                            ],
                          ],
                        );
                      },
                    ),
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

bool _isItemOverdue(WorkItem item) {
  final dueAt = item.dueAt;
  if (dueAt == null || item.completedAt != null) return false;
  final today = DateTime.now();
  final normalizedToday = DateTime(today.year, today.month, today.day);
  final normalizedDue = DateTime(dueAt.year, dueAt.month, dueAt.day);
  return normalizedDue.isBefore(normalizedToday);
}

String _minutesLabel(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final remaining = minutes % 60;
  return remaining == 0 ? '${hours}h' : '${hours}h ${remaining}m';
}

String _hierarchyPath({
  required WorkItem item,
  required List<WorkItem> allItems,
}) {
  final byId = {for (final entry in allItems) entry.itemId: entry};
  final path = <String>[];
  WorkItem? cursor = item;
  final visited = <String>{};
  while (cursor != null && visited.add(cursor.itemId)) {
    path.insert(0, cursor.title);
    cursor = cursor.parentId == null ? null : byId[cursor.parentId!];
  }
  return path.join(' / ');
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
  return '${localizations.formatMediumDate(date)} '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
}

String? _relativeDateHint(DateTime date, {bool overdue = false}) {
  final today = DateTime.now();
  final normalizedToday = DateTime(today.year, today.month, today.day);
  final normalizedDate = DateTime(date.year, date.month, date.day);
  final delta = normalizedDate.difference(normalizedToday).inDays;
  if (delta == 0) return overdue ? 'Earlier today' : 'Today';
  if (delta == 1) return 'Tomorrow';
  if (delta == -1) return 'Yesterday';
  if (delta > 1) return 'In $delta days';
  return '${delta.abs()} days ago';
}

String _recurrenceSummary(WorkItemRecurrence recurrence) {
  final cadence = switch (recurrence.cadence) {
    WorkItemRecurrenceCadence.daily => 'Daily',
    WorkItemRecurrenceCadence.weekly => 'Weekly',
    WorkItemRecurrenceCadence.customDays => 'Custom days',
  };
  return '$cadence every ${recurrence.interval}';
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
  String? subtitle,
  required Widget child,
}) {
  final theme = Theme.of(context);
  return Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
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
  final theme = Theme.of(context);
  return ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 124, maxWidth: 180),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: emphasized
            ? theme.colorScheme.errorContainer.withValues(alpha: 0.5)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: emphasized
                ? theme.colorScheme.onErrorContainer
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(
              hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
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
  required IconData icon,
}) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: theme.textTheme.bodyMedium),
            ],
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
  final theme = Theme.of(context);
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.55,
          ),
          borderRadius: BorderRadius.circular(15),
        ),
        alignment: Alignment.center,
        child: Icon(
          _activityIcon(event.type),
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _activityLabel(event.type),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _formatDetailsDateTime(context, event.createdAt.toLocal()),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
