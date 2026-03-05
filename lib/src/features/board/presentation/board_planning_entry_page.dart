import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_navigation_shell.dart';
import '../../../app_routes.dart';
import 'board_controller.dart';

class BoardPlanningEntryPage extends ConsumerWidget {
  const BoardPlanningEntryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedView = ref.watch(boardPlanningViewProvider);

    return AppPrimaryScaffold(
      activeRoute: AppRoutes.planning,
      title: 'Planning',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Planning Entry Point',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Use this surface to choose your planning lens. Full planning views are expanded in Phase 6.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          SegmentedButton<BoardPlanningView>(
            segments: const [
              ButtonSegment(
                value: BoardPlanningView.kanban,
                icon: Icon(Icons.view_kanban_outlined),
                label: Text('Kanban'),
              ),
              ButtonSegment(
                value: BoardPlanningView.hierarchy,
                icon: Icon(Icons.account_tree_outlined),
                label: Text('Hierarchy'),
              ),
              ButtonSegment(
                value: BoardPlanningView.backlog,
                icon: Icon(Icons.list_alt_outlined),
                label: Text('Backlog'),
              ),
              ButtonSegment(
                value: BoardPlanningView.focus,
                icon: Icon(Icons.filter_center_focus_outlined),
                label: Text('Focus'),
              ),
            ],
            selected: {selectedView},
            onSelectionChanged: (selection) {
              ref.read(boardPlanningViewProvider.notifier).state =
                  selection.first;
            },
          ),
          const SizedBox(height: 16),
          for (final view in BoardPlanningView.values)
            Card(
              child: ListTile(
                leading: Icon(
                  view == selectedView
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(_viewLabel(view)),
                subtitle: Text(_viewDescription(view)),
                trailing: view == selectedView
                    ? const Chip(label: Text('Active'))
                    : null,
                onTap: () {
                  ref.read(boardPlanningViewProvider.notifier).state = view;
                },
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pushReplacementNamed(AppRoutes.workspace);
            },
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Open Workspace With Selected View'),
          ),
        ],
      ),
    );
  }

  String _viewLabel(BoardPlanningView view) {
    return switch (view) {
      BoardPlanningView.kanban => 'Kanban Workspace',
      BoardPlanningView.hierarchy => 'Hierarchy Planning',
      BoardPlanningView.backlog => 'Backlog Grooming',
      BoardPlanningView.focus => 'Focus Context',
    };
  }

  String _viewDescription(BoardPlanningView view) {
    return switch (view) {
      BoardPlanningView.kanban =>
        'Column-based execution with drag-and-drop movement.',
      BoardPlanningView.hierarchy =>
        'Parent/child structure for goals, projects, tasks, and actions.',
      BoardPlanningView.backlog =>
        'Prioritized queue and next-up candidate review.',
      BoardPlanningView.focus =>
        'Narrowed context around one item and its related nodes.',
    };
  }
}
