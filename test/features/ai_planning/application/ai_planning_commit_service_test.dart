import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/core/outbox/in_memory_outbox_queue.dart';
import 'package:plandone/src/features/ai_planning/application/ai_planning_commit_service.dart';
import 'package:plandone/src/features/ai_planning/domain/ai_planning_draft.dart';
import 'package:plandone/src/features/board/data/local/in_memory_local_board_store.dart';
import 'package:plandone/src/features/board/data/repositories/board_repository_impl.dart';
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';

void main() {
  test('approved draft commits through local store and outbox with hierarchy',
      () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outbox = InMemoryOutboxQueue();
    final repository = BoardRepositoryImpl(
      localStore: localStore,
      outboxQueue: outbox,
      currentUserId: 'user-1',
    );
    final service = AiPlanningCommitService(repository: repository);
    final snapshot = await localStore.getBoard('board-1');
    final draft = AiPlanningDraft(
      prompt: 'Plan a controlled launch with a short execution hierarchy.',
      summary: 'A small reviewed plan.',
      providerName: 'test provider',
      createdAt: DateTime(2026, 8, 26),
      items: const [
        AiPlanningDraftItem(
          draftId: 'action',
          title: 'Run release smoke test',
          type: WorkItemType.action,
          parentDraftId: 'task',
          estimatedEffortMinutes: 30,
        ),
        AiPlanningDraftItem(
          draftId: 'goal',
          title: 'Ship a reliable release',
          type: WorkItemType.goal,
        ),
        AiPlanningDraftItem(
          draftId: 'task',
          title: 'Validate the release',
          type: WorkItemType.task,
          parentDraftId: 'goal',
        ),
      ],
    );

    final result = await service.commit(draft: draft, snapshot: snapshot);

    expect(result.createdItems, hasLength(3));
    final createdByTitle = {
      for (final item in result.createdItems) item.title: item,
    };
    expect(
      createdByTitle['Validate the release']!.parentId,
      createdByTitle['Ship a reliable release']!.itemId,
    );
    expect(
      createdByTitle['Run release smoke test']!.parentId,
      createdByTitle['Validate the release']!.itemId,
    );
    expect(
      createdByTitle['Run release smoke test']!.tags,
      contains('ai-assisted'),
    );

    final localSnapshot = await localStore.getBoard('board-1');
    expect(
      localSnapshot.items.where((item) => item.tags.contains('ai-assisted')),
      hasLength(3),
    );
    final pending = await outbox.listPending();
    expect(pending.where((operation) => operation.entity == 'workItem'),
        hasLength(3));
  });

  test('invalid board requirements fail before creating any draft items',
      () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outbox = InMemoryOutboxQueue();
    final repository = BoardRepositoryImpl(
      localStore: localStore,
      outboxQueue: outbox,
      currentUserId: 'user-1',
    );
    final service = AiPlanningCommitService(repository: repository);
    final original = await localStore.getBoard('board-1');
    await localStore.upsertBoard(
      original.board.copyWith(
        validationSettings:
            original.board.validationSettings.copyWith(requireDueDate: true),
      ),
    );
    final snapshot = await localStore.getBoard('board-1');
    final draft = AiPlanningDraft(
      prompt: 'Plan a launch that would otherwise create one goal item.',
      summary: 'One item.',
      providerName: 'test provider',
      createdAt: DateTime(2026, 8, 26),
      items: const [
        AiPlanningDraftItem(
          draftId: 'goal',
          title: 'Ship safely',
          type: WorkItemType.goal,
        ),
      ],
    );

    await expectLater(
      service.commit(draft: draft, snapshot: snapshot),
      throwsA(
        isA<AiPlanningException>().having(
          (error) => error.message,
          'message',
          contains('requires dates'),
        ),
      ),
    );
    final after = await localStore.getBoard('board-1');
    expect(after.items.any((item) => item.title == 'Ship safely'), isFalse);
    expect(await outbox.listPending(), isEmpty);
  });

  test('approved draft roots attach to an existing item without duplicating it',
      () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outbox = InMemoryOutboxQueue();
    final repository = BoardRepositoryImpl(
      localStore: localStore,
      outboxQueue: outbox,
      currentUserId: 'user-1',
    );
    final service = AiPlanningCommitService(repository: repository);
    final snapshot = await localStore.getBoard('board-1');
    final existingGoal =
        snapshot.items.firstWhere((item) => item.itemId == 'g-1');
    final draft = AiPlanningDraft(
      prompt: 'Extend the existing goal with a focused release project.',
      summary: 'New descendants only.',
      providerName: 'test provider',
      createdAt: DateTime(2026, 8, 26),
      existingParentItemId: existingGoal.itemId,
      items: const [
        AiPlanningDraftItem(
          draftId: 'project',
          title: 'Prepare the next release',
          type: WorkItemType.project,
        ),
        AiPlanningDraftItem(
          draftId: 'task',
          title: 'Verify the release candidate',
          type: WorkItemType.task,
          parentDraftId: 'project',
        ),
      ],
    );

    final result = await service.commit(draft: draft, snapshot: snapshot);

    expect(result.createdItems, hasLength(2));
    final project = result.createdItems
        .firstWhere((item) => item.title == 'Prepare the next release');
    final task = result.createdItems
        .firstWhere((item) => item.title == 'Verify the release candidate');
    expect(project.parentId, existingGoal.itemId);
    expect(task.parentId, project.itemId);
    final after = await localStore.getBoard('board-1');
    expect(
      after.items.where((item) => item.title == existingGoal.title),
      hasLength(1),
    );
  });

  test('approved sibling order is preserved during commit', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outbox = InMemoryOutboxQueue();
    final repository = BoardRepositoryImpl(
      localStore: localStore,
      outboxQueue: outbox,
      currentUserId: 'user-1',
    );
    final service = AiPlanningCommitService(repository: repository);
    final snapshot = await localStore.getBoard('board-1');
    final draft = AiPlanningDraft(
      prompt: 'Create one goal with two reviewed tasks in a chosen order.',
      summary: 'Sibling ordering.',
      providerName: 'test provider',
      createdAt: DateTime(2026, 8, 29),
      items: const [
        AiPlanningDraftItem(
          draftId: 'goal',
          title: 'Ordered goal',
          type: WorkItemType.goal,
        ),
        AiPlanningDraftItem(
          draftId: 'task-b',
          title: 'Second task moved first',
          type: WorkItemType.task,
          parentDraftId: 'goal',
        ),
        AiPlanningDraftItem(
          draftId: 'task-a',
          title: 'First task moved second',
          type: WorkItemType.task,
          parentDraftId: 'goal',
        ),
      ],
    );

    final result = await service.commit(draft: draft, snapshot: snapshot);

    expect(
      result.createdItems.map((item) => item.title),
      ['Ordered goal', 'Second task moved first', 'First task moved second'],
    );
  });
}
