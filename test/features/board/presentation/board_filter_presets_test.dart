import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plandone/src/core/outbox/in_memory_outbox_queue.dart';
import 'package:plandone/src/features/board/data/local/in_memory_local_board_store.dart';
import 'package:plandone/src/features/board/presentation/board_controller.dart';

void main() {
  ProviderContainer _container() {
    return ProviderContainer(
      overrides: [
        localBoardStoreProvider.overrideWith(
          (ref) => InMemoryLocalBoardStore(currentUserId: 'user-1'),
        ),
        outboxQueueProvider.overrideWith(
          (ref) => InMemoryOutboxQueue(),
        ),
      ],
    );
  }

  test('save + apply filter preset restores canonical filter context',
      () async {
    final container = _container();
    addTearDown(container.dispose);

    container.read(boardVisibilityFilterProvider.notifier).state =
        BoardVisibilityFilter.actionsOnly;
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
        BoardVisibilityFilter.allItems;
    container.read(boardItemStateFilterProvider.notifier).state =
        BoardItemStateFilter.any;
    container.read(boardTagFilterProvider.notifier).state = '';
    container.read(boardTextQueryProvider.notifier).state = '';
    container.read(workspaceSelectedBoardIdsProvider.notifier).state = {};
    container.read(showArchivedOnlyProvider.notifier).state = false;
    container.read(boardPlanningViewProvider.notifier).state =
        BoardPlanningView.kanban;

    await container.read(boardControllerProvider).applyFilterPreset(saved);

    expect(container.read(boardVisibilityFilterProvider),
        BoardVisibilityFilter.actionsOnly);
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
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(boardControllerProvider);
    final saved = await controller.saveCurrentFilterPreset(name: 'Delete me');

    await controller.deleteFilterPreset(saved.presetId);

    final presets = await container.read(boardFilterPresetsProvider.future);
    expect(presets.where((p) => p.presetId == saved.presetId), isEmpty);
  });
}
