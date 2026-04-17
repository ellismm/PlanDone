import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plandone/src/core/outbox/in_memory_outbox_queue.dart';
import 'package:plandone/src/features/auth/presentation/auth_controller.dart';
import 'package:plandone/src/features/board/data/local/in_memory_local_board_store.dart';
import 'package:plandone/src/features/board/data/repositories/board_filter_preset_repository_impl.dart';
import 'package:plandone/src/features/board/data/repositories/work_item_activity_repository_impl.dart';
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';
import 'package:plandone/src/features/board/presentation/board_controller.dart';

void main() {
  ProviderContainer buildContainer() {
    return ProviderContainer(
      overrides: [
        activeUserIdProvider.overrideWith((ref) => 'user-1'),
        localBoardStoreProvider.overrideWith(
          (ref) => InMemoryLocalBoardStore(currentUserId: 'user-1'),
        ),
        outboxQueueProvider.overrideWith(
          (ref) => InMemoryOutboxQueue(),
        ),
        workItemActivityRepositoryProvider.overrideWith(
          (ref) => InMemoryWorkItemActivityRepository(),
        ),
        boardFilterPresetRepositoryProvider.overrideWith(
          (ref) => InMemoryBoardFilterPresetRepository(),
        ),
      ],
    );
  }

  test('save + apply filter preset restores canonical filter context',
      () async {
    final container = buildContainer();
    addTearDown(container.dispose);

    container.read(boardVisibilityFilterProvider.notifier).state = {
      WorkItemType.action
    };
    container.read(boardItemStateFilterProvider.notifier).state =
        BoardItemStateFilter.urgent;
    container.read(boardTagFilterProvider.notifier).state = 'phase11';
    container.read(boardTextQueryProvider.notifier).state = 'search-text';
    container.read(workspaceSelectedBoardIdsProvider.notifier).state = {
      'board-1'
    };
    container.read(showArchivedOnlyProvider.notifier).state = true;
    container.read(boardPlanningViewProvider.notifier).state =
        BoardPlanningView.backlog;

    final saved = await container
        .read(boardControllerProvider)
        .saveCurrentFilterPreset(name: 'My Preset');

    container.read(boardVisibilityFilterProvider.notifier).state =
        <WorkItemType>{};
    container.read(boardItemStateFilterProvider.notifier).state =
        BoardItemStateFilter.any;
    container.read(boardTagFilterProvider.notifier).state = '';
    container.read(boardTextQueryProvider.notifier).state = '';
    container.read(workspaceSelectedBoardIdsProvider.notifier).state = {};
    container.read(showArchivedOnlyProvider.notifier).state = false;
    container.read(boardPlanningViewProvider.notifier).state =
        BoardPlanningView.kanban;

    await container.read(boardControllerProvider).applyFilterPreset(saved);

    expect(
      container.read(boardVisibilityFilterProvider),
      {WorkItemType.action},
    );
    expect(container.read(boardItemStateFilterProvider),
        BoardItemStateFilter.urgent);
    expect(container.read(boardTagFilterProvider), 'phase11');
    expect(container.read(boardTextQueryProvider), 'search-text');
    expect(container.read(workspaceSelectedBoardIdsProvider), {'board-1'});
    expect(container.read(showArchivedOnlyProvider), isTrue);
    expect(
        container.read(boardPlanningViewProvider), BoardPlanningView.backlog);
  });

  test('delete filter preset removes it from stored list', () async {
    final container = buildContainer();
    addTearDown(container.dispose);

    final controller = container.read(boardControllerProvider);
    final saved = await controller.saveCurrentFilterPreset(name: 'Delete me');

    await controller.deleteFilterPreset(saved.presetId);

    final presets = await container.read(boardFilterPresetsProvider.future);
    expect(presets.where((p) => p.presetId == saved.presetId), isEmpty);
  });

  test('setPlanningView resets hierarchy mode to full-tree context', () {
    final container = buildContainer();
    addTearDown(container.dispose);

    container.read(boardVisibilityFilterProvider.notifier).state = {
      WorkItemType.action
    };
    container.read(boardItemStateFilterProvider.notifier).state =
        BoardItemStateFilter.blocked;
    container.read(boardTagFilterProvider.notifier).state = 'tagged';
    container.read(boardTextQueryProvider.notifier).state = 'search';
    container.read(focusModeEnabledProvider.notifier).state = true;
    container.read(focusedItemIdProvider.notifier).state = 'a-3';
    container.read(showOverdueOnlyProvider.notifier).state = true;
    container.read(showDueSoonOnlyProvider.notifier).state = true;
    container.read(showArchivedOnlyProvider.notifier).state = true;
    container.read(collapsedHierarchyItemIdsProvider.notifier).state = {'g-1'};

    container
        .read(boardControllerProvider)
        .setPlanningView(BoardPlanningView.hierarchy);

    expect(
        container.read(boardPlanningViewProvider), BoardPlanningView.hierarchy);
    expect(container.read(boardVisibilityFilterProvider), isEmpty);
    expect(
        container.read(boardItemStateFilterProvider), BoardItemStateFilter.any);
    expect(container.read(boardTagFilterProvider), isEmpty);
    expect(container.read(boardTextQueryProvider), isEmpty);
    expect(container.read(focusModeEnabledProvider), isFalse);
    expect(container.read(focusedItemIdProvider), isNull);
    expect(container.read(showOverdueOnlyProvider), isFalse);
    expect(container.read(showDueSoonOnlyProvider), isFalse);
    expect(container.read(showArchivedOnlyProvider), isFalse);
    expect(container.read(collapsedHierarchyItemIdsProvider), isEmpty);
  });

  test('clearFocusedItem clears focus selection and focus mode', () {
    final container = buildContainer();
    addTearDown(container.dispose);

    container.read(focusedItemIdProvider.notifier).state = 'a-3';
    container.read(focusModeEnabledProvider.notifier).state = true;

    container.read(boardControllerProvider).clearFocusedItem();

    expect(container.read(focusedItemIdProvider), isNull);
    expect(container.read(focusModeEnabledProvider), isFalse);
  });

  test('kanban doing auto-focus resets when leaving and re-entering kanban',
      () {
    final container = buildContainer();
    addTearDown(container.dispose);

    expect(container.read(lastAutoFocusedDoingBoardIdProvider), isNull);

    container.read(lastAutoFocusedDoingBoardIdProvider.notifier).state =
        defaultBoardId;
    expect(
      container.read(lastAutoFocusedDoingBoardIdProvider),
      defaultBoardId,
    );

    container
        .read(boardControllerProvider)
        .setPlanningView(BoardPlanningView.hierarchy);
    expect(container.read(lastAutoFocusedDoingBoardIdProvider), isNull);

    container.read(lastAutoFocusedDoingBoardIdProvider.notifier).state =
        defaultBoardId;
    container.read(boardWorkspaceSurfaceProvider.notifier).state =
        BoardWorkspaceSurface.inbox;
    expect(container.read(lastAutoFocusedDoingBoardIdProvider), isNull);
  });
}
