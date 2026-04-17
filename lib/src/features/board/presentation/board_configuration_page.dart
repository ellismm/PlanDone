// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_navigation_shell.dart';
import '../../../app_routes.dart';
import '../../../core/help/app_help.dart';
import '../../../core/help/app_help_controller.dart';
import '../../../core/help/app_help_widgets.dart';
import '../../../core/account/account_management_controller.dart';
import '../../../core/theme/plan_done_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../../auth/domain/models/auth_failure.dart';
import '../../auth/domain/models/auth_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/models/board.dart';
import '../domain/models/board_backup_document.dart';
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
import 'board_view_ui.dart';
import 'hierarchy_visuals.dart';

const _configurationBoardScopeHelpSpec = AppHelpTargetSpec(
  id: AppHelpTargetIds.configurationBoardScope,
  title: 'Board scope',
  description:
      'This section controls which board you are configuring right now.',
  whenToUse:
      'Use it when you want to switch boards, create a new one, rename the current one, or delete a board you no longer need.',
  whatHappens:
      'The rest of the configuration page updates to match the currently selected board.',
  icon: Icons.dashboard_customize_outlined,
  tourId: AppHelpTourId.configuration,
);

const _configurationBoardSettingsHelpSpec = AppHelpTargetSpec(
  id: AppHelpTargetIds.configurationBoardSettings,
  title: 'Board settings',
  description:
      'These settings shape how the board behaves, not just how it looks.',
  whenToUse:
      'Use this section when you need to change validation rules, workflow defaults, reminders, theme, or backup behavior.',
  whatHappens:
      'Each entry opens a focused setup surface so you can change one system at a time without losing context.',
  icon: Icons.tune_outlined,
  tourId: AppHelpTourId.configuration,
);

const _configurationAccountHelpSpec = AppHelpTargetSpec(
  id: AppHelpTargetIds.configurationAccount,
  title: 'Account controls',
  description:
      'This is where you manage your account, device unlock behavior, and destructive account actions.',
  whenToUse:
      'Use it when you need to sign out, enable fingerprint quick unlock, or intentionally delete the account.',
  whatHappens:
      'Account actions take effect on this device immediately, and delete account requires a deliberate confirmation.',
  icon: Icons.account_circle_outlined,
  tourId: AppHelpTourId.configuration,
);

const _configurationColumnsHelpSpec = AppHelpTargetSpec(
  id: AppHelpTargetIds.configurationColumns,
  title: 'Columns',
  description:
      'Columns define the statuses and semantics the board uses day to day.',
  whenToUse:
      'Use this section when you want to add, rename, reorder, hide, or retune the meaning of columns.',
  whatHappens:
      'Changing columns updates how items can move through the board and what status choices appear elsewhere in the app.',
  icon: Icons.view_column_outlined,
  tourId: AppHelpTourId.configuration,
);

const _configurationHelpHelpSpec = AppHelpTargetSpec(
  id: AppHelpTargetIds.configurationHelp,
  title: 'Help settings',
  description:
      'This section controls the in-app help system and lets you replay guided tours.',
  whenToUse:
      'Use it when you want the floating ? button on screen or you want to revisit how Flow or Calendar work.',
  whatHappens:
      'You can turn the floating help button on or off and restart the small guided tours any time.',
  icon: Icons.help_outline,
  tourId: AppHelpTourId.configuration,
);

class BoardConfigurationPage extends ConsumerWidget {
  const BoardConfigurationPage({super.key});

  String _workflowKindLabel(BoardColumnKind kind) {
    return switch (kind) {
      BoardColumnKind.custom => 'Custom',
      BoardColumnKind.planning => 'Planning',
      BoardColumnKind.backlog => 'Backlog',
      BoardColumnKind.ready => 'Ready',
      BoardColumnKind.inProgress => 'In progress',
      BoardColumnKind.blocked => 'Blocked',
      BoardColumnKind.urgent => 'Urgent',
      BoardColumnKind.review => 'Review',
      BoardColumnKind.done => 'Done',
      BoardColumnKind.cancelled => 'Cancelled',
    };
  }

  String _planningViewLabel(BoardPlanningView view) {
    return switch (view) {
      BoardPlanningView.kanban => 'Kanban',
      BoardPlanningView.hierarchy => 'Hierarchy',
      BoardPlanningView.backlog => 'Backlog',
      BoardPlanningView.focus => 'Focus',
      BoardPlanningView.calendar => 'Calendar',
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
    } on AuthFailure catch (error) {
      _showActionFeedback(context, error.message);
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

  Future<bool> _confirmDeleteAccount(
    BuildContext context, {
    required AuthSession session,
  }) async {
    var confirmationText = '';

    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: const Text('Delete account permanently?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This deletes the PlanDone account for ${session.user.email ?? session.user.displayName ?? session.user.uid}.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This also clears the local workspace data cached for this account on this device. Exported backup files are not deleted automatically.',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Type DELETE to continue.',
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (value) {
                      setState(() {
                        confirmationText = value.trim().toUpperCase();
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Confirmation',
                      hintText: 'DELETE',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  onPressed: confirmationText == 'DELETE'
                      ? () => Navigator.of(dialogContext).pop(true)
                      : null,
                  child: const Text('Delete account'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    return shouldDelete;
  }

  Future<void> _showAboutHelpSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
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
                'How PlanDone is meant to feel',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'PlanDone is meant to help a regular person capture what matters, decide what to do next, and keep moving without turning life into a corporate workflow.',
              ),
              const SizedBox(height: 12),
              const Text(
                'A simple rhythm usually works best:',
              ),
              const SizedBox(height: 8),
              const Text(
                '1. Capture quickly.\n2. Triage in Workspace or Flow.\n3. Place dated work in Calendar.\n4. Review signals in Insights when you want a pulse check.',
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

  String _formatBackupTimestamp(DateTime value) {
    final local = value.toLocal();
    String two(int input) => input.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _showBackupRestoreSheet(
    BuildContext context,
    WidgetRef ref, {
    required BoardSnapshot snapshot,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final backupsAsync = ref.watch(boardBackupsProvider);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Backup & Restore',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Export the current board to app-managed JSON and restore a backup as a new board snapshot.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () async {
                      BoardBackupFile? exported;
                      final ok = await _runGuardedAction(
                        context,
                        () async {
                          exported = await ref
                              .read(boardControllerProvider)
                              .exportCurrentBoardBackup();
                        },
                      );
                      if (!ok || exported == null || !context.mounted) return;
                      _showActionFeedback(
                        context,
                        'Backup saved: ${exported!.fileName}',
                      );
                    },
                    icon: const Icon(Icons.download_outlined),
                    label: Text('Export "${snapshot.board.name}"'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Saved backups',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: backupsAsync.when(
                      data: (backups) {
                        if (backups.isEmpty) {
                          return const Center(
                            child: Text('No backups saved yet.'),
                          );
                        }
                        return ListView.separated(
                          shrinkWrap: true,
                          itemCount: backups.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final backup = backups[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(backup.boardName),
                              subtitle: Text(
                                'Saved ${_formatBackupTimestamp(backup.exportedAt)}',
                              ),
                              trailing: Wrap(
                                spacing: 4,
                                children: [
                                  TextButton(
                                    onPressed: () async {
                                      final shouldRestore =
                                          await _confirmDestructiveAction(
                                        context,
                                        title: 'Restore backup?',
                                        message:
                                            'Restore "${backup.boardName}" as a new board? This will not overwrite the current board.',
                                        confirmLabel: 'Restore',
                                      );
                                      if (!shouldRestore) return;
                                      final ok = await _runGuardedAction(
                                        context,
                                        () => ref
                                            .read(boardControllerProvider)
                                            .importBoardBackup(
                                              backupPath: backup.path,
                                            ),
                                      );
                                      if (ok && context.mounted) {
                                        Navigator.of(context).pop();
                                        _showActionFeedback(
                                          context,
                                          'Backup restored as a new board.',
                                        );
                                      }
                                    },
                                    child: const Text('Restore'),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      final shouldDelete =
                                          await _confirmDestructiveAction(
                                        context,
                                        title: 'Delete backup?',
                                        message:
                                            'Delete the saved backup "${backup.fileName}"?',
                                        confirmLabel: 'Delete',
                                      );
                                      if (!shouldDelete) return;
                                      final ok = await _runGuardedAction(
                                        context,
                                        () => ref
                                            .read(boardControllerProvider)
                                            .deleteBoardBackup(
                                              backupPath: backup.path,
                                            ),
                                      );
                                      if (ok && context.mounted) {
                                        _showActionFeedback(
                                          context,
                                          'Backup deleted.',
                                        );
                                      }
                                    },
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                      loading: () => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      error: (error, _) => Center(
                        child: Text('Unable to load backups: $error'),
                      ),
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
    var enableImmediately = true;

    final submitted =
        await showDialog<(bool, WorkflowTemplateColumnSpec, String, bool)>(
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
                          Navigator.of(context).pop(
                            (true, selectedSpec, name, enableImmediately),
                          );
                        },
                      ),
                  ],
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: enableImmediately,
                    title: const Text('Show in board immediately'),
                    subtitle: Text(
                      enableImmediately
                          ? 'This column will appear in workspace views right away.'
                          : 'This column will stay hidden until you enable it later.',
                    ),
                    onChanged: (value) =>
                        setState(() => enableImmediately = value),
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
                  if (cannotAddAnyPredefined) return;
                  if (useCustom) {
                    final name = customName.trim();
                    if (name.isEmpty) return;
                    Navigator.of(context).pop(
                      (true, selectedSpec, name, enableImmediately),
                    );
                    return;
                  }
                  Navigator.of(context).pop(
                    (
                      false,
                      selectedSpec,
                      selectedSpec.name,
                      enableImmediately,
                    ),
                  );
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
    final shouldEnableImmediately = submitted.$4;
    if (chosenName.isEmpty) return;

    await _runGuardedAction(context, () async {
      final existingColumnIds = {
        for (final column in snapshot.columns) column.columnId
      };
      await ref.read(boardControllerProvider).createColumn(chosenName);
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
            kind: isCustom ? null : chosenSpec.kind,
            isDoneState: isCustom ? null : chosenSpec.isDoneState,
            isBlockedState: isCustom ? null : chosenSpec.isBlockedState,
            isCancelledState: isCustom ? null : chosenSpec.isCancelledState,
            isEnabled: shouldEnableImmediately,
          );
    });
  }

  Future<void> _showColumnSettingsDialog(
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
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Column settings: ${column.name}'),
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
                  contentPadding: EdgeInsets.zero,
                  value: isDoneState,
                  title: const Text('Done state'),
                  onChanged: (value) => setState(() => isDoneState = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isBlockedState,
                  title: const Text('Blocked state'),
                  onChanged: (value) => setState(() => isBlockedState = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isCancelledState,
                  title: const Text('Cancelled state'),
                  onChanged: (value) =>
                      setState(() => isCancelledState = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isEnabled,
                  title: const Text('Show in board'),
                  subtitle: Text(
                    isEnabled
                        ? 'Visible in workspace and drag targets'
                        : 'Hidden from workspace and drag targets',
                  ),
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
                  () => ref.read(boardControllerProvider).updateColumnSemantics(
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
        ),
      ),
    );
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
    ref.read(boardControllerProvider).setPlanningView(selected);
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
    final authSessionAsync = ref.watch(authSessionProvider);
    final biometricStatusAsync = ref.watch(biometricQuickUnlockStatusProvider);
    final notificationPreferencesAsync =
        ref.watch(notificationPreferencesProvider);
    final autofillSettingsAsync = ref.watch(autofillSettingsProvider);
    final planningView = ref.watch(boardPlanningViewProvider);
    final activeTheme = ref.watch(themeControllerProvider).valueOrNull ??
        PlanDoneThemeKey.calmFocus;
    final showFloatingHelpButton = ref.watch(appHelpShowFloatingButtonProvider);
    final completedTours = ref.watch(appHelpCompletedToursProvider);

    return AppPrimaryScaffold(
      activeRoute: AppRoutes.boardConfiguration,
      title: 'Board Configuration',
      helpSurface: AppHelpSurfaceId.configuration,
      workspaceIcon: boardPlanningViewIcon(planningView),
      workspaceSelectedIcon: boardPlanningViewSelectedIcon(planningView),
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
              AppHelpTarget(
                spec: _configurationBoardScopeHelpSpec,
                borderRadius: BorderRadius.circular(16),
                child: Card(
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
              AppHelpTarget(
                spec: _configurationBoardSettingsHelpSpec,
                borderRadius: BorderRadius.circular(16),
                child: Card(
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
                        title: const Text('Default Workspace View'),
                        subtitle: Text(
                          'Default workspace surface: ${_planningViewLabel(planningView)}',
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
                        title: const Text('Reminders & Quiet Hours'),
                        subtitle: Text(notificationPreferencesAsync.when(
                          data: (preferences) => preferences.enabled
                              ? 'Due/start reminders, snooze defaults, and mute windows are configured per user.'
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
                          error: (_, __) =>
                              'Unable to load settings right now.',
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
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('Backup & Restore'),
                        subtitle: const Text(
                          'Export JSON backups locally and restore them as new boards.',
                        ),
                        trailing: const Icon(Icons.backup_outlined),
                        onTap: () => _showBackupRestoreSheet(
                          context,
                          ref,
                          snapshot: snapshot,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AppHelpTarget(
                spec: _configurationAccountHelpSpec,
                borderRadius: BorderRadius.circular(16),
                child: Card(
                  child: authSessionAsync.when(
                    loading: () => const ListTile(
                      title: Text('Account'),
                      subtitle: Text('Loading account...'),
                      trailing: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    error: (_, __) => const ListTile(
                      title: Text('Account'),
                      subtitle: Text('Unable to load account right now.'),
                    ),
                    data: (session) {
                      if (session == null) {
                        return const ListTile(
                          title: Text('Account'),
                          subtitle: Text('Not signed in.'),
                        );
                      }

                      final accountLabel = session.user.displayName
                                  ?.trim()
                                  .isNotEmpty ==
                              true
                          ? '${session.user.displayName} • ${session.user.email ?? session.user.uid}'
                          : (session.user.email ?? session.user.uid);

                      return Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.account_circle_outlined),
                            title: const Text('Account'),
                            subtitle: Text(accountLabel),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            title: const Text('Fingerprint quick unlock'),
                            subtitle: Text(
                              biometricStatusAsync.when(
                                data: (status) {
                                  if (status ==
                                      BiometricQuickUnlockStatus.enabled) {
                                    return 'Enabled for this Android device.';
                                  }
                                  if (status ==
                                      BiometricQuickUnlockStatus.disabled) {
                                    return 'Available on this Android device.';
                                  }
                                  return 'Unavailable on this device.';
                                },
                                loading: () => 'Checking device support...',
                                error: (_, __) =>
                                    'Unable to read quick unlock status right now.',
                              ),
                            ),
                            trailing: TextButton(
                              onPressed: biometricStatusAsync.valueOrNull ==
                                          BiometricQuickUnlockStatus
                                              .unsupported ||
                                      biometricStatusAsync.isLoading
                                  ? null
                                  : () async {
                                      final controller = ref.read(
                                        accountManagementControllerProvider,
                                      );
                                      final enable = biometricStatusAsync
                                              .valueOrNull ==
                                          BiometricQuickUnlockStatus.disabled;
                                      final ok = await _runGuardedAction(
                                        context,
                                        () => enable
                                            ? controller
                                                .enableBiometricQuickUnlock()
                                            : controller
                                                .disableBiometricQuickUnlock(),
                                      );
                                      if (!ok || !context.mounted) return;
                                      _showActionFeedback(
                                        context,
                                        enable
                                            ? 'Fingerprint quick unlock enabled.'
                                            : 'Fingerprint quick unlock disabled.',
                                      );
                                    },
                              child: Text(
                                biometricStatusAsync.valueOrNull ==
                                        BiometricQuickUnlockStatus.enabled
                                    ? 'Disable'
                                    : 'Enable',
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.logout),
                            title: const Text('Sign out'),
                            subtitle: const Text(
                              'Sign out of PlanDone on this device.',
                            ),
                            onTap: () => _runGuardedAction(
                              context,
                              () => ref
                                  .read(accountManagementControllerProvider)
                                  .signOut(),
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: Icon(
                              Icons.delete_forever_outlined,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            title: Text(
                              'Delete account',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            subtitle: const Text(
                              'Permanently delete this account and clear its local workspace cache on this device.',
                            ),
                            onTap: () async {
                              final shouldDelete = await _confirmDeleteAccount(
                                context,
                                session: session,
                              );
                              if (!shouldDelete || !context.mounted) return;
                              await _runGuardedAction(
                                context,
                                () => ref
                                    .read(accountManagementControllerProvider)
                                    .deleteCurrentAccount(),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              AppHelpTarget(
                spec: _configurationHelpHelpSpec,
                borderRadius: BorderRadius.circular(16),
                child: Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: showFloatingHelpButton,
                        title: const Text('Floating help button'),
                        subtitle: const Text(
                          'Keep a small ? button on screen so Help mode is always within reach.',
                        ),
                        onChanged: (value) {
                          ref
                              .read(appHelpControllerProvider)
                              .setShowFloatingHelpButton(value);
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.dashboard_outlined),
                        title: const Text('Replay Workspace walkthrough'),
                        subtitle: Text(
                          completedTours.contains(AppHelpTourId.workspace)
                              ? 'Run through the guided Workspace walkthrough again.'
                              : 'Start the Workspace walkthrough.',
                        ),
                        onTap: () async {
                          ref
                              .read(boardControllerProvider)
                              .setPlanningView(BoardPlanningView.kanban);
                          await ref.read(appHelpControllerProvider).startTour(
                                AppHelpTourId.workspace,
                              );
                          if (!context.mounted) return;
                          Navigator.of(context)
                              .pushReplacementNamed(AppRoutes.workspace);
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.account_tree_outlined),
                        title: const Text('Replay Hierarchy walkthrough'),
                        subtitle: Text(
                          completedTours.contains(AppHelpTourId.hierarchy)
                              ? 'Run through the guided Hierarchy walkthrough again.'
                              : 'Start the Hierarchy walkthrough.',
                        ),
                        onTap: () async {
                          ref
                              .read(boardControllerProvider)
                              .setPlanningView(BoardPlanningView.hierarchy);
                          await ref.read(appHelpControllerProvider).startTour(
                                AppHelpTourId.hierarchy,
                              );
                          if (!context.mounted) return;
                          Navigator.of(context)
                              .pushReplacementNamed(AppRoutes.workspace);
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.insights_outlined),
                        title: const Text('Replay Insights walkthrough'),
                        subtitle: Text(
                          completedTours.contains(AppHelpTourId.insights)
                              ? 'Run through the guided Insights walkthrough again.'
                              : 'Start the Insights walkthrough.',
                        ),
                        onTap: () async {
                          await ref.read(appHelpControllerProvider).startTour(
                                AppHelpTourId.insights,
                              );
                          if (!context.mounted) return;
                          Navigator.of(context)
                              .pushReplacementNamed(AppRoutes.insights);
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.settings_outlined),
                        title: const Text('Replay Configuration walkthrough'),
                        subtitle: Text(
                          completedTours.contains(AppHelpTourId.configuration)
                              ? 'Run through the guided Configuration walkthrough again.'
                              : 'Start the Configuration walkthrough.',
                        ),
                        onTap: () async {
                          await ref.read(appHelpControllerProvider).startTour(
                                AppHelpTourId.configuration,
                              );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.auto_awesome_motion_outlined),
                        title: const Text('Replay Flow walkthrough'),
                        subtitle: Text(
                          completedTours.contains(AppHelpTourId.flow)
                              ? 'Run through the guided Flow walkthrough again.'
                              : 'Start the Flow walkthrough.',
                        ),
                        onTap: () async {
                          await ref.read(appHelpControllerProvider).startTour(
                                AppHelpTourId.flow,
                              );
                          if (!context.mounted) return;
                          Navigator.of(context)
                              .pushReplacementNamed(AppRoutes.flow);
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.calendar_today_outlined),
                        title: const Text('Replay Calendar walkthrough'),
                        subtitle: Text(
                          completedTours.contains(AppHelpTourId.calendar)
                              ? 'Run through the guided Calendar walkthrough again.'
                              : 'Start the Calendar walkthrough.',
                        ),
                        onTap: () async {
                          ref
                              .read(boardControllerProvider)
                              .setPlanningView(BoardPlanningView.calendar);
                          await ref.read(appHelpControllerProvider).startTour(
                                AppHelpTourId.calendar,
                              );
                          if (!context.mounted) return;
                          Navigator.of(context)
                              .pushReplacementNamed(AppRoutes.workspace);
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: const Text('About PlanDone help'),
                        subtitle: const Text(
                          'A quick explanation of the app’s intended everyday rhythm.',
                        ),
                        onTap: () => _showAboutHelpSheet(context),
                      ),
                    ],
                  ),
                ),
              ),
              AppHelpTarget(
                spec: _configurationColumnsHelpSpec,
                borderRadius: BorderRadius.circular(16),
                child: Card(
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
                          Builder(
                            builder: (context) {
                              final column = columns[index];
                              final summaryBits = <String>[
                                'Order: ${index + 1}',
                                _workflowKindLabel(column.kind),
                                column.isEnabled ? 'Visible' : 'Hidden',
                                if (column.isBlockedState) 'Blocked',
                                if (column.isDoneState) 'Done',
                                if (column.isCancelledState) 'Cancelled',
                              ];

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(column.name),
                                subtitle: Text(summaryBits.join(' • ')),
                                trailing: Wrap(
                                  spacing: 0,
                                  children: [
                                    IconButton(
                                      tooltip: 'Column settings',
                                      onPressed: canManageBoard
                                          ? () => _showColumnSettingsDialog(
                                                context,
                                                ref,
                                                column: column,
                                              )
                                          : null,
                                      icon: const Icon(Icons.tune),
                                    ),
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
                                                    .read(
                                                        boardControllerProvider)
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
                                                    .read(
                                                        boardControllerProvider)
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
                                                column: column,
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
                                                column: column,
                                                canDelete: columns.length > 1,
                                              )
                                          : null,
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
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
