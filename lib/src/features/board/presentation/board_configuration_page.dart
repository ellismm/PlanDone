import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_navigation_shell.dart';
import '../../../app_routes.dart';
import '../../../core/theme/plan_done_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../domain/models/board.dart';
import '../domain/models/board_failures.dart';
import '../domain/models/board_member.dart';
import '../domain/models/board_snapshot.dart';
import '../domain/models/board_validation_settings.dart';
import '../domain/models/board_workflow_settings.dart';
import '../domain/models/column.dart';
import '../domain/models/autofill_settings.dart';
import '../domain/models/notification_preferences.dart';
import '../domain/models/work_item_type.dart';
import '../domain/policies/board_permissions.dart';
import '../domain/policies/workflow_semantics_policy.dart';
import 'board_controller.dart';
import 'hierarchy_visuals.dart';

class BoardConfigurationPage extends ConsumerWidget {
  const BoardConfigurationPage({super.key});

  String _planningViewLabel(BoardPlanningView view) {
    return switch (view) {
      BoardPlanningView.kanban => 'Kanban',
      BoardPlanningView.hierarchy => 'Hierarchy',
      BoardPlanningView.backlog => 'Backlog',
      BoardPlanningView.focus => 'Focus',
    };
  }

  void _showActionFeedback(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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

  Future<void> _showCreateBoardDialog(
      BuildContext context, WidgetRef ref) async {
    String boardName = '';

    final submittedName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
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
      ),
    );

    final name = submittedName?.trim();
    if (name == null || name.isEmpty) return;
    await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).createBoard(name),
    );
  }

  Future<void> _showRenameBoardDialog(
    BuildContext context,
    WidgetRef ref, {
    required String currentName,
  }) async {
    String boardName = currentName;
    final submittedName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename board'),
        content: TextField(
          autofocus: true,
          decoration: InputDecoration(hintText: currentName),
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
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    final name = submittedName?.trim();
    if (name == null || name.isEmpty || name == currentName) return;
    await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).renameBoard(name),
    );
  }

  Future<void> _confirmDeleteBoard(
    BuildContext context,
    WidgetRef ref, {
    required String boardName,
  }) async {
    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete board?'),
            content: Text(
              'Delete "$boardName"? This removes the board and all its local items/columns/members from this workspace. This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldDelete) return;
    await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).deleteCurrentBoard(),
    );
  }

  Future<void> _showAddColumnDialog(
    BuildContext context,
    WidgetRef ref, {
    required BoardSnapshot snapshot,
  }) async {
    final predefined = WorkflowSemanticsPolicy.designatedStarterTemplate;
    final existingKinds = {for (final column in snapshot.columns) column.kind};
    final workflow = snapshot.board.workflowSettings;
    final canUseCustom = workflow.allowCustomColumns;

    final defaultSpec = predefined
        .where((spec) => !existingKinds.contains(spec.kind))
        .cast<WorkflowTemplateColumnSpec?>()
        .firstWhere((_) => true, orElse: () => null);
    var selectedSpec = defaultSpec ?? predefined.first;
    var useCustom = false;
    var customName = '';

    final submitted =
        await showDialog<(bool, WorkflowTemplateColumnSpec, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final availableSpecs = canUseCustom
              ? predefined
              : predefined
                  .where((spec) => !existingKinds.contains(spec.kind))
                  .toList();
          final selectedStillAvailable = availableSpecs
              .any((candidate) => candidate.kind == selectedSpec.kind);
          if (!selectedStillAvailable && availableSpecs.isNotEmpty) {
            selectedSpec = availableSpecs.first;
          }
          final cannotAddAnyPredefined =
              !canUseCustom && availableSpecs.isEmpty;

          return AlertDialog(
            title: const Text('Add column'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Choose a predefined column type:'),
                  const SizedBox(height: 8),
                  if (availableSpecs.isNotEmpty)
                    DropdownButtonFormField<WorkflowTemplateColumnSpec>(
                      initialValue: selectedSpec,
                      items: [
                        for (final spec in availableSpecs)
                          DropdownMenuItem(
                            value: spec,
                            child: Text(spec.name),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => selectedSpec = value);
                      },
                    )
                  else
                    Text(
                      'All predefined columns are already present.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 8),
                  if (!canUseCustom)
                    Text(
                      'Custom columns are disabled for this workflow. Only predefined columns can be added.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (canUseCustom) ...[
                    const Divider(height: 24),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: useCustom,
                      title: const Text('Create custom column instead'),
                      onChanged: (value) => setState(() => useCustom = value),
                    ),
                    if (useCustom)
                      TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                            hintText: 'Custom column name'),
                        textInputAction: TextInputAction.done,
                        onChanged: (value) => customName = value,
                        onSubmitted: (value) {
                          final name = value.trim();
                          if (name.isEmpty) return;
                          Navigator.of(context).pop((true, selectedSpec, name));
                        },
                      ),
                  ],
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
                  if (cannotAddAnyPredefined) return;
                  if (useCustom) {
                    final name = customName.trim();
                    if (name.isEmpty) return;
                    Navigator.of(context).pop((true, selectedSpec, name));
                    return;
                  }
                  Navigator.of(context)
                      .pop((false, selectedSpec, selectedSpec.name));
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );

    if (submitted == null) return;

    final isCustom = submitted.$1;
    final chosenSpec = submitted.$2;
    final chosenName = submitted.$3.trim();
    if (chosenName.isEmpty) return;

    await _runGuardedAction(context, () async {
      final existingColumnIds = {
        for (final column in snapshot.columns) column.columnId
      };
      await ref.read(boardControllerProvider).createColumn(chosenName);
      if (isCustom) return;

      final updated = await ref.read(localBoardStoreProvider).getBoard(
            snapshot.board.boardId,
          );
      final createdColumn = updated.columns
          .where((column) => !existingColumnIds.contains(column.columnId))
          .cast<BoardColumn?>()
          .firstWhere((_) => true, orElse: () => null);
      if (createdColumn == null) return;

      await ref.read(boardControllerProvider).updateColumnSemantics(
            columnId: createdColumn.columnId,
            kind: chosenSpec.kind,
            isDoneState: chosenSpec.isDoneState,
            isBlockedState: chosenSpec.isBlockedState,
            isCancelledState: chosenSpec.isCancelledState,
            isEnabled: chosenSpec.isEnabledByDefault,
          );
    });
  }

  Future<void> _showRenameColumnDialog(
    BuildContext context,
    WidgetRef ref, {
    required BoardColumn column,
  }) async {
    String name = column.name;
    final submittedName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename column'),
        content: TextField(
          autofocus: true,
          decoration: InputDecoration(hintText: column.name),
          textInputAction: TextInputAction.done,
          onChanged: (value) => name = value,
          onSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed.isEmpty) return;
            Navigator.of(context).pop(trimmed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = name.trim();
              if (trimmed.isEmpty) return;
              Navigator.of(context).pop(trimmed);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    final trimmed = submittedName?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == column.name) return;
    await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).renameColumn(
            columnId: column.columnId,
            name: trimmed,
          ),
    );
  }

  Future<void> _confirmDeleteColumn(
    BuildContext context,
    WidgetRef ref, {
    required BoardColumn column,
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
            content: Text(
              'Delete "${column.name}"? Items will be moved to another column.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!shouldDelete) return;

    await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).deleteColumn(column.columnId),
    );
  }

  String _roleLabel(BoardRole role) {
    final name = role.name;
    return '${name[0].toUpperCase()}${name.substring(1)}';
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
      builder: (context) => StatefulBuilder(
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
                  Text(
                    'Board members',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
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
                            value: BoardRole.viewer,
                            child: Text('Viewer'),
                          ),
                          DropdownMenuItem(
                            value: BoardRole.member,
                            child: Text('Member'),
                          ),
                          DropdownMenuItem(
                            value: BoardRole.admin,
                            child: Text('Admin'),
                          ),
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
                            () =>
                                ref.read(boardControllerProvider).inviteMember(
                                      userId: uid,
                                      role: inviteRole,
                                    ),
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

                        return ListTile(
                          dense: true,
                          title: Text(member.userId),
                          subtitle: Text(
                            pending
                                ? '${_roleLabel(member.role)} • Invite pending'
                                : _roleLabel(member.role),
                          ),
                          trailing: Wrap(
                            spacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (isOwner)
                                const Chip(label: Text('Owner'))
                              else
                                DropdownButton<BoardRole>(
                                  value: member.role,
                                  items: const [
                                    DropdownMenuItem(
                                      value: BoardRole.viewer,
                                      child: Text('Viewer'),
                                    ),
                                    DropdownMenuItem(
                                      value: BoardRole.member,
                                      child: Text('Member'),
                                    ),
                                    DropdownMenuItem(
                                      value: BoardRole.admin,
                                      child: Text('Admin'),
                                    ),
                                  ],
                                  onChanged: (value) async {
                                    if (value == null || value == member.role) {
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
                                onPressed: isOwner
                                    ? null
                                    : () async {
                                        final confirmed =
                                            await _confirmDestructiveAction(
                                          context,
                                          title: member.userId == currentUserId
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
                                icon: const Icon(Icons.person_remove_outlined),
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
      ),
    );
  }

  Future<void> _showValidationSettingsDialog(
    BuildContext context,
    WidgetRef ref, {
    required BoardValidationSettings initial,
    required BoardSnapshot snapshot,
  }) async {
    var settings = initial;
    final topLevelGoals = snapshot.items
        .where(
            (item) => item.type == WorkItemType.goal && item.parentId == null)
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
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
                        settings =
                            settings.copyWith(requireParentForProjects: value);
                      });
                    },
                  ),
                  SwitchListTile(
                    value: settings.requireParentForTasks,
                    title: const Text('Require parent for tasks'),
                    onChanged: (value) {
                      setState(() {
                        settings =
                            settings.copyWith(requireParentForTasks: value);
                      });
                    },
                  ),
                  SwitchListTile(
                    value: settings.requireParentForActions,
                    title: const Text('Require parent for actions'),
                    onChanged: (value) {
                      setState(() {
                        settings =
                            settings.copyWith(requireParentForActions: value);
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
                        settings =
                            settings.copyWith(enforceParentTypeOrder: value);
                      });
                    },
                  ),
                  const Divider(),
                  Text(
                    'Metadata visibility',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  SwitchListTile(
                    value: settings.showStartDate,
                    title: const Text('Show start date'),
                    onChanged: (value) {
                      setState(() {
                        settings = settings.copyWith(showStartDate: value);
                      });
                    },
                  ),
                  SwitchListTile(
                    value: settings.showTargetEndDate,
                    title: const Text('Show target end date'),
                    onChanged: (value) {
                      setState(() {
                        settings = settings.copyWith(showTargetEndDate: value);
                      });
                    },
                  ),
                  SwitchListTile(
                    value: settings.showDueDate,
                    title: const Text('Show due date'),
                    onChanged: (value) {
                      setState(() {
                        settings = settings.copyWith(showDueDate: value);
                      });
                    },
                  ),
                  SwitchListTile(
                    value: settings.showCreatedDate,
                    title: const Text('Show created date'),
                    onChanged: (value) {
                      setState(() {
                        settings = settings.copyWith(showCreatedDate: value);
                      });
                    },
                  ),
                  SwitchListTile(
                    value: settings.showCompletedDate,
                    title: const Text('Show completed date'),
                    onChanged: (value) {
                      setState(() {
                        settings = settings.copyWith(showCompletedDate: value);
                      });
                    },
                  ),
                  SwitchListTile(
                    value: settings.showEstimatedEffort,
                    title: const Text('Show estimated effort'),
                    onChanged: (value) {
                      setState(() {
                        settings =
                            settings.copyWith(showEstimatedEffort: value);
                      });
                    },
                  ),
                  SwitchListTile(
                    value: settings.showActualEffort,
                    title: const Text('Show actual effort'),
                    onChanged: (value) {
                      setState(() {
                        settings = settings.copyWith(showActualEffort: value);
                      });
                    },
                  ),
                  const Divider(),
                  Text(
                    'Metadata required',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  SwitchListTile(
                    value: settings.requireStartDate,
                    title: const Text('Require start date'),
                    onChanged: (value) {
                      setState(() {
                        settings = settings.copyWith(requireStartDate: value);
                      });
                    },
                  ),
                  SwitchListTile(
                    value: settings.requireTargetEndDate,
                    title: const Text('Require target end date'),
                    onChanged: (value) {
                      setState(() {
                        settings =
                            settings.copyWith(requireTargetEndDate: value);
                      });
                    },
                  ),
                  SwitchListTile(
                    value: settings.requireDueDate,
                    title: const Text('Require due date'),
                    onChanged: (value) {
                      setState(() {
                        settings = settings.copyWith(requireDueDate: value);
                      });
                    },
                  ),
                  SwitchListTile(
                    value: settings.requireEstimatedEffort,
                    title: const Text('Require estimated effort'),
                    onChanged: (value) {
                      setState(() {
                        settings =
                            settings.copyWith(requireEstimatedEffort: value);
                      });
                    },
                  ),
                  const Divider(),
                  Text(
                    'Hierarchy visuals',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  SwitchListTile(
                    value: settings.hierarchyColorGroupingByGoal,
                    title: const Text('Color-group by top-level goal'),
                    subtitle: const Text(
                      'Adds restrained color accents for hierarchy branches.',
                    ),
                    onChanged: (value) {
                      setState(() {
                        settings = settings.copyWith(
                          hierarchyColorGroupingByGoal: value,
                        );
                      });
                    },
                  ),
                  DropdownButtonFormField<HierarchyParentPathMode>(
                    initialValue: settings.hierarchyParentPathMode,
                    decoration: const InputDecoration(
                      labelText: 'Parent path on card',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: HierarchyParentPathMode.visible,
                        child: Text('Visible'),
                      ),
                      DropdownMenuItem(
                        value: HierarchyParentPathMode.subtle,
                        child: Text('Subtle'),
                      ),
                      DropdownMenuItem(
                        value: HierarchyParentPathMode.hidden,
                        child: Text('Hidden'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        settings = settings.copyWith(
                          hierarchyParentPathMode: value,
                        );
                      });
                    },
                  ),
                  if (topLevelGoals.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Goal color overrides',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    for (final goal in topLevelGoals)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: DropdownButtonFormField<int?>(
                          initialValue:
                              settings.hierarchyGoalColorOverrides[goal.itemId],
                          decoration: InputDecoration(
                            labelText: goal.title,
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Auto color'),
                            ),
                            for (var i = 0;
                                i < hierarchyGoalColorPalette.length;
                                i++)
                              DropdownMenuItem<int?>(
                                value: hierarchyGoalColorPalette[i],
                                child: Row(
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color:
                                            Color(hierarchyGoalColorPalette[i]),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text('Palette ${i + 1}'),
                                  ],
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              final next = Map<String, int>.from(
                                settings.hierarchyGoalColorOverrides,
                              );
                              if (value == null) {
                                next.remove(goal.itemId);
                              } else {
                                next[goal.itemId] = value;
                              }
                              settings = settings.copyWith(
                                hierarchyGoalColorOverrides: next,
                              );
                            });
                          },
                        ),
                      ),
                  ],
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
      ),
    );
  }

  Future<void> _showWorkflowSettingsDialog(
    BuildContext context,
    WidgetRef ref, {
    required BoardSnapshot snapshot,
  }) async {
    var workflow = snapshot.board.workflowSettings;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
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
                        workflow = workflow.copyWith(allowCustomColumns: value);
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
      ),
    );
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
                    title: const Text('Suggest type'),
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

  Future<void> _showWorkspaceViewDialog(
    BuildContext context,
    WidgetRef ref, {
    required BoardPlanningView current,
  }) async {
    final selected = await showDialog<BoardPlanningView>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Workspace view'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final view in BoardPlanningView.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: view == current
                    ? const Icon(Icons.check, size: 18)
                    : const SizedBox(width: 18),
                title: Text(_planningViewLabel(view)),
                onTap: () {
                  Navigator.of(context).pop(view);
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selected == null) return;
    ref.read(boardPlanningViewProvider.notifier).state = selected;
  }

  Future<void> _showThemeDialog(
    BuildContext context,
    WidgetRef ref, {
    required PlanDoneThemeKey current,
  }) async {
    final maxDialogHeight = MediaQuery.sizeOf(context).height * 0.62;
    final selected = await showDialog<PlanDoneThemeKey>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Theme'),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxDialogHeight),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final theme in PlanDoneThemeKey.values)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: theme == current
                        ? const Icon(Icons.check, size: 18)
                        : const SizedBox(width: 18),
                    title: Text(PlanDoneThemes.label(theme)),
                    onTap: () {
                      Navigator.of(context).pop(theme);
                    },
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selected == null) return;
    await ref.read(themeControllerProvider.notifier).setTheme(selected);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardAsync = ref.watch(boardStreamProvider);
    final boardsAsync = ref.watch(boardsProvider);
    final permissionProfile = ref.watch(boardPermissionProfileProvider);
    final canManageBoard =
        permissionProfile?.has(BoardCapability.manageBoard) ?? false;
    final isBoardOwner = permissionProfile?.member?.role == BoardRole.owner;
    final canManageMembers =
        permissionProfile?.has(BoardCapability.manageMembers) ?? false;
    final canConfigureValidation =
        permissionProfile?.has(BoardCapability.configureValidation) ?? false;
    final canJoinInvite =
        permissionProfile?.has(BoardCapability.joinInvite) ?? false;
    final currentUserId = ref.watch(boardScopeUserIdProvider);
    final currentBoardId = ref.watch(currentBoardIdProvider);
    final notificationPreferencesAsync =
        ref.watch(notificationPreferencesProvider);
    final autofillSettingsAsync = ref.watch(autofillSettingsProvider);
    final planningView = ref.watch(boardPlanningViewProvider);
    final activeTheme = ref.watch(themeControllerProvider).valueOrNull ??
        PlanDoneThemeKey.calmFocus;

    return AppPrimaryScaffold(
      activeRoute: AppRoutes.boardConfiguration,
      title: 'Board Configuration',
      actions: [
        if (canJoinInvite)
          IconButton(
            tooltip: 'Accept board invite',
            onPressed: () {
              _runGuardedAction(
                context,
                () => ref.read(boardControllerProvider).acceptInvite(),
              );
            },
            icon: const Icon(Icons.how_to_reg_outlined),
          ),
      ],
      body: boardAsync.when(
        data: (snapshot) {
          final boards = boardsAsync.valueOrNull ?? const <Board>[];
          final columns = [...snapshot.columns]
            ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Board Scope',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final board in boards)
                            ChoiceChip(
                              label: Text(board.name),
                              selected: board.boardId == currentBoardId,
                              onSelected: (_) {
                                ref
                                    .read(boardControllerProvider)
                                    .switchBoard(board.boardId);
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: canManageBoard
                                ? () => _showCreateBoardDialog(context, ref)
                                : null,
                            icon: const Icon(Icons.add),
                            label: const Text('Create Board'),
                          ),
                          OutlinedButton.icon(
                            onPressed: canManageBoard
                                ? () => _showRenameBoardDialog(
                                      context,
                                      ref,
                                      currentName: snapshot.board.name,
                                    )
                                : null,
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Rename Board'),
                          ),
                          OutlinedButton.icon(
                            onPressed: isBoardOwner
                                ? () => _confirmDeleteBoard(
                                      context,
                                      ref,
                                      boardName: snapshot.board.name,
                                    )
                                : null,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Delete Board'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  title: const Text('Members & Roles'),
                  subtitle: Text(
                    canManageMembers
                        ? 'Invite members, update roles, remove access.'
                        : 'You do not have permission to manage members.',
                  ),
                  trailing: const Icon(Icons.group_outlined),
                  onTap: canManageMembers
                      ? () => _showMemberManagementSheet(
                            context,
                            ref,
                            snapshot: snapshot,
                            currentUserId: currentUserId,
                          )
                      : null,
                ),
              ),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('Validation Rules'),
                      subtitle: Text(
                        canConfigureValidation
                            ? 'Configure required parent/type constraints.'
                            : 'You do not have permission to configure validation.',
                      ),
                      trailing: const Icon(Icons.rule_folder_outlined),
                      onTap: canConfigureValidation
                          ? () => _showValidationSettingsDialog(
                                context,
                                ref,
                                initial: snapshot.board.validationSettings,
                                snapshot: snapshot,
                              )
                          : null,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('Workflow Template'),
                      subtitle: Text(
                        canManageBoard
                            ? 'Choose starter flow and custom-column policy.'
                            : 'You do not have permission to manage board workflow.',
                      ),
                      trailing: const Icon(Icons.route_outlined),
                      onTap: canManageBoard
                          ? () => _showWorkflowSettingsDialog(
                                context,
                                ref,
                                snapshot: snapshot,
                              )
                          : null,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('Workspace View'),
                      subtitle: Text(
                        'Default planning surface: ${_planningViewLabel(planningView)}',
                      ),
                      trailing: const Icon(Icons.view_kanban_outlined),
                      onTap: () => _showWorkspaceViewDialog(
                        context,
                        ref,
                        current: planningView,
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('Theme'),
                      subtitle: Text(PlanDoneThemes.label(activeTheme)),
                      trailing: const Icon(Icons.palette_outlined),
                      onTap: () => _showThemeDialog(
                        context,
                        ref,
                        current: activeTheme,
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('Notification Preferences'),
                      subtitle: Text(notificationPreferencesAsync.when(
                        data: (preferences) => preferences.enabled
                            ? 'Due/start reminders configured per user.'
                            : 'Reminders are disabled for this user.',
                        loading: () => 'Loading preferences...',
                        error: (_, __) =>
                            'Unable to load preferences right now.',
                      )),
                      trailing: const Icon(Icons.notifications_outlined),
                      onTap: notificationPreferencesAsync.valueOrNull == null
                          ? null
                          : () => _showNotificationPreferencesDialog(
                                context,
                                ref,
                                initial: notificationPreferencesAsync.value!,
                              ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('Autofill Suggestions'),
                      subtitle: Text(autofillSettingsAsync.when(
                        data: (settings) => settings.enabled
                            ? 'Deterministic defaults enabled for create/triage.'
                            : 'Autofill suggestions are disabled.',
                        loading: () => 'Loading settings...',
                        error: (_, __) => 'Unable to load settings right now.',
                      )),
                      trailing: const Icon(Icons.auto_awesome_outlined),
                      onTap: autofillSettingsAsync.valueOrNull == null
                          ? null
                          : () => _showAutofillSettingsDialog(
                                context,
                                ref,
                                initial: autofillSettingsAsync.value!,
                              ),
                    ),
                  ],
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Columns',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Add column',
                            onPressed: canManageBoard
                                ? () => _showAddColumnDialog(
                                      context,
                                      ref,
                                      snapshot: snapshot,
                                    )
                                : null,
                            icon: const Icon(Icons.add_box_outlined),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      for (var index = 0; index < columns.length; index++)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(columns[index].name),
                          subtitle: Text('Order: ${index + 1}'),
                          trailing: Wrap(
                            spacing: 0,
                            children: [
                              IconButton(
                                tooltip: 'Move left',
                                onPressed: !canManageBoard || index == 0
                                    ? null
                                    : () {
                                        final order = [
                                          for (final column in columns)
                                            column.columnId
                                        ];
                                        final id = order.removeAt(index);
                                        order.insert(index - 1, id);
                                        _runGuardedAction(
                                          context,
                                          () => ref
                                              .read(boardControllerProvider)
                                              .reorderColumns(order),
                                        );
                                      },
                                icon: const Icon(Icons.chevron_left),
                              ),
                              IconButton(
                                tooltip: 'Move right',
                                onPressed: !canManageBoard ||
                                        index >= columns.length - 1
                                    ? null
                                    : () {
                                        final order = [
                                          for (final column in columns)
                                            column.columnId
                                        ];
                                        final id = order.removeAt(index);
                                        order.insert(index + 1, id);
                                        _runGuardedAction(
                                          context,
                                          () => ref
                                              .read(boardControllerProvider)
                                              .reorderColumns(order),
                                        );
                                      },
                                icon: const Icon(Icons.chevron_right),
                              ),
                              IconButton(
                                tooltip: 'Rename column',
                                onPressed: canManageBoard
                                    ? () => _showRenameColumnDialog(
                                          context,
                                          ref,
                                          column: columns[index],
                                        )
                                    : null,
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Delete column',
                                onPressed: canManageBoard
                                    ? () => _confirmDeleteColumn(
                                          context,
                                          ref,
                                          column: columns[index],
                                          canDelete: columns.length > 1,
                                        )
                                    : null,
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text('Error: $error'),
        ),
      ),
    );
  }
}
