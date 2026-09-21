import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/app_routes.dart';
import 'package:plandone/src/core/outbox/in_memory_outbox_queue.dart';
import 'package:plandone/src/features/ai_planning/domain/ai_planning_draft.dart';
import 'package:plandone/src/features/ai_planning/domain/ai_planning_provider.dart';
import 'package:plandone/src/features/ai_planning/presentation/ai_planning_controller.dart';
import 'package:plandone/src/features/ai_planning/presentation/ai_planning_page.dart';
import 'package:plandone/src/features/auth/presentation/auth_controller.dart';
import 'package:plandone/src/features/board/data/local/in_memory_local_board_store.dart';
import 'package:plandone/src/features/board/data/repositories/work_item_activity_repository_impl.dart';
import 'package:plandone/src/features/board/domain/models/board_validation_settings.dart';
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';
import 'package:plandone/src/features/board/presentation/board_controller.dart';

class _FakeAiPlanningProvider implements AiPlanningProvider {
  AiPlanningRequest? lastRequest;

  @override
  String get displayName => 'Test AI';

  @override
  bool get isAvailable => true;

  @override
  Future<AiPlanningDraft> generate(AiPlanningRequest request) async {
    lastRequest = request;
    final usesExistingParent =
        request.placementMode == AiPlanningPlacementMode.existingParent;
    return AiPlanningDraft(
      prompt: request.prompt,
      summary: 'A proposal that remains staged until approval.',
      providerName: displayName,
      createdAt: DateTime(2026, 8, 26),
      existingParentItemId:
          usesExistingParent ? request.requestedParentItemId : null,
      items: usesExistingParent
          ? const [
              AiPlanningDraftItem(
                draftId: 'project',
                title: 'AI staged project',
                type: WorkItemType.project,
              ),
              AiPlanningDraftItem(
                draftId: 'task',
                title: 'AI staged task',
                type: WorkItemType.task,
                parentDraftId: 'project',
              ),
              AiPlanningDraftItem(
                draftId: 'action',
                title: 'AI staged action',
                type: WorkItemType.action,
                parentDraftId: 'task',
              ),
              AiPlanningDraftItem(
                draftId: 'task-second',
                title: 'AI staged second task',
                type: WorkItemType.task,
                parentDraftId: 'project',
              ),
            ]
          : const [
              AiPlanningDraftItem(
                draftId: 'goal',
                title: 'AI staged goal',
                type: WorkItemType.goal,
              ),
              AiPlanningDraftItem(
                draftId: 'task',
                title: 'AI staged task',
                type: WorkItemType.task,
                parentDraftId: 'goal',
              ),
            ],
    );
  }
}

void main() {
  testWidgets('draft does not write until explicit approval', (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outbox = InMemoryOutboxQueue();
    final aiProvider = _FakeAiPlanningProvider();
    const existingGoalColor = 0xFFAD1457;
    final initialSnapshot = await localStore.getBoard('board-1');
    await localStore.upsertBoard(
      initialSnapshot.board.copyWith(
        validationSettings: const BoardValidationSettings(
          hierarchyColorGroupingByGoal: true,
          hierarchyGoalColorOverrides: {'g-1': existingGoalColor},
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeUserIdProvider.overrideWith((ref) => 'user-1'),
          localBoardStoreProvider.overrideWith((ref) => localStore),
          outboxQueueProvider.overrideWith((ref) => outbox),
          workItemActivityRepositoryProvider.overrideWith(
            (ref) => InMemoryWorkItemActivityRepository(),
          ),
          aiPlanningProviderProvider.overrideWithValue(
            aiProvider,
          ),
        ],
        child: MaterialApp(
          home: const AiPlanningPage(),
          routes: {
            AppRoutes.workspace: (_) => const Scaffold(
                  body: Text('Workspace after approval'),
                ),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Full • Goal → Project → Task → Action'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('ai-planning-prompt')),
      'Extend Ship PlanDone MVP with one project and one validation task.',
    );
    expect(find.text('Automatic — match the prompt'), findsOneWidget);
    final generateButton = find.byKey(const ValueKey('generate-ai-plan'));
    await tester.ensureVisible(generateButton);
    await tester.tap(generateButton);
    await tester.pumpAndSettle();

    expect(find.text('Review before approval'), findsOneWidget);
    expect(aiProvider.lastRequest?.placementMode,
        AiPlanningPlacementMode.existingParent);
    expect(aiProvider.lastRequest?.requestedParentItemId, 'g-1');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('ai-existing-parent-context')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Ship PlanDone MVP'), findsWidgets);
    expect(find.byKey(const ValueKey('ai-existing-parent-context')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('ai-draft-tree-project')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-draft-tree-task')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-draft-tree-action')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ai-draft-tree-task-second')),
      findsOneWidget,
    );
    final accent = tester.widget<Container>(
      find.byKey(const ValueKey('ai-draft-accent-project')),
    );
    expect((accent.decoration! as BoxDecoration).color,
        const Color(existingGoalColor));
    var snapshot = await localStore.getBoard('board-1');
    expect(snapshot.items.any((item) => item.title == 'AI staged project'),
        isFalse);
    expect(await outbox.listPending(), isEmpty);

    final secondTaskMoveUp =
        find.byKey(const ValueKey('ai-draft-move-up-task-second'));
    await tester.ensureVisible(secondTaskMoveUp);
    await tester.tap(secondTaskMoveUp);
    await tester.pumpAndSettle();
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('ai-draft-tree-task-second')))
          .dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('ai-draft-tree-task'))).dy,
      ),
    );

    final approveButton = find.byKey(const ValueKey('approve-ai-plan'));
    await tester.ensureVisible(approveButton);
    await tester.tap(approveButton);
    await tester.pumpAndSettle();
    expect(find.text('Add approved plan?'), findsOneWidget);
    await tester.tap(find.text('Approve and add'));
    await tester.pumpAndSettle();

    expect(find.text('Workspace after approval'), findsOneWidget);
    snapshot = await localStore.getBoard('board-1');
    final existingGoal =
        snapshot.items.firstWhere((item) => item.itemId == 'g-1');
    final project =
        snapshot.items.firstWhere((item) => item.title == 'AI staged project');
    final task =
        snapshot.items.firstWhere((item) => item.title == 'AI staged task');
    final secondTask = snapshot.items
        .firstWhere((item) => item.title == 'AI staged second task');
    final action =
        snapshot.items.firstWhere((item) => item.title == 'AI staged action');
    expect(project.parentId, existingGoal.itemId);
    expect(task.parentId, project.itemId);
    expect(secondTask.parentId, project.itemId);
    expect(action.parentId, task.itemId);
    expect(task.tags, contains('ai-assisted'));
    final pending = await outbox.listPending();
    expect(pending, hasLength(4));
    final createdTitles = pending
        .map((operation) => operation.payload['title'])
        .whereType<String>()
        .toList();
    expect(
      createdTitles.indexOf('AI staged second task'),
      lessThan(createdTitles.indexOf('AI staged task')),
    );
  });
}
