import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plandone/src/app.dart';
import 'package:plandone/src/app_routes.dart';
import 'package:plandone/src/core/account/account_data_cleanup_service.dart';
import 'package:plandone/src/core/account/account_management_controller.dart';
import 'package:plandone/src/core/help/app_help.dart';
import 'package:plandone/src/core/help/app_help_controller.dart';
import 'package:plandone/src/core/outbox/in_memory_outbox_queue.dart';
import 'package:plandone/src/core/runtime/runtime_flags.dart';
import 'package:plandone/src/core/theme/theme_controller.dart';
import 'package:plandone/src/core/theme/theme_settings_repository.dart';
import 'package:plandone/src/features/auth/data/data_sources/in_memory_auth_data_source.dart';
import 'package:plandone/src/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:plandone/src/features/auth/data/services/biometric_quick_unlock_service.dart';
import 'package:plandone/src/features/auth/domain/models/auth_user.dart';
import 'package:plandone/src/features/auth/presentation/auth_controller.dart';
import 'package:plandone/src/features/board/data/local/in_memory_local_board_store.dart';
import 'package:plandone/src/features/board/data/repositories/autofill_settings_repository_impl.dart';
import 'package:plandone/src/features/board/data/repositories/board_calendar_preferences_repository_impl.dart';
import 'package:plandone/src/features/board/data/repositories/board_flow_preferences_repository_impl.dart';
import 'package:plandone/src/features/board/data/repositories/board_filter_preset_repository_impl.dart';
import 'package:plandone/src/features/board/data/repositories/in_memory/hierarchy_view_preferences_repository_in_memory.dart';
import 'package:plandone/src/features/board/data/repositories/notification_preferences_repository_impl.dart';
import 'package:plandone/src/features/board/data/repositories/work_item_activity_repository_impl.dart';
import 'package:plandone/src/features/board/domain/models/board_flow.dart';
import 'package:plandone/src/features/board/domain/models/board_calendar_preferences.dart';
import 'package:plandone/src/features/board/domain/models/board_reminder_alert.dart';
import 'package:plandone/src/features/board/domain/models/board_insights.dart';
import 'package:plandone/src/features/board/domain/models/column.dart';
import 'package:plandone/src/features/board/domain/models/work_item.dart';
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';
import 'package:plandone/src/features/board/presentation/board_controller.dart';
import 'package:plandone/src/features/board/presentation/board_calendar_view.dart';
import 'package:plandone/src/features/board/presentation/workspace_attention.dart';

const _signedInSession = AuthSession(
  user: AuthUser(
    uid: 'user-1',
    email: 'user-1@plandone.dev',
    displayName: 'User One',
  ),
);

ProviderContainer _createTestContainer(
  AuthSession? initialSession, {
  List<Override> overrides = const [],
}) {
  final userId = initialSession?.user.uid ?? 'guest';
  return ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWith(
        (ref) => AuthRepositoryImpl(
          InMemoryAuthDataSource(initialSession: initialSession),
        ),
      ),
      themeSettingsRepositoryProvider.overrideWith(
        (ref) => InMemoryThemeSettingsRepository(),
      ),
      localBoardStoreProvider.overrideWith(
        (ref) => InMemoryLocalBoardStore(currentUserId: userId),
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
      boardCalendarPreferencesRepositoryProvider.overrideWith(
        (ref) => InMemoryBoardCalendarPreferencesRepository(userId: userId),
      ),
      boardFlowPreferencesRepositoryProvider.overrideWith(
        (ref) => InMemoryBoardFlowPreferencesRepository(userId: userId),
      ),
      hierarchyViewPreferencesRepositoryProvider.overrideWith(
        (ref) => InMemoryHierarchyViewPreferencesRepository(userId: userId),
      ),
      appHelpPreferencesRepositoryProvider.overrideWith(
        (ref) => InMemoryAppHelpPreferencesRepository(userId: userId),
      ),
      autofillSettingsRepositoryProvider.overrideWith(
        (ref) => InMemoryAutofillSettingsRepository(userId: userId),
      ),
      notificationPreferencesRepositoryProvider.overrideWith(
        (ref) => InMemoryNotificationPreferencesRepository(userId: userId),
      ),
      reminderClockProvider.overrideWith(
        (ref) => Stream<DateTime>.value(DateTime(2026, 3, 19, 9)),
      ),
      ...overrides,
    ],
  );
}

Widget _buildAppWithContainer(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const PlanDoneApp(),
  );
}

Finder _bottomNavLabel(String label) {
  return find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );
}

Finder _railLabel(String label) {
  return find.descendant(
    of: find.byType(NavigationRail),
    matching: find.text(label),
  );
}

BoardReminderAlert _testReminder({
  String reminderId = 'a-3|due|1710835200000|60',
  bool overdue = true,
}) {
  final referenceAt = DateTime(2026, 3, 19, 8);
  return BoardReminderAlert(
    reminderId: reminderId,
    kind: BoardReminderKind.due,
    item: WorkItem(
      itemId: 'a-3',
      boardId: 'board-1',
      parentId: 't-2',
      title: 'Add parent-child navigation in item cards',
      type: WorkItemType.action,
      columnId: 'c-doing',
      dueAt: referenceAt,
      createdAt: referenceAt,
      updatedAt: referenceAt,
    ),
    boardName: 'My Board',
    triggerAt: referenceAt.subtract(const Duration(hours: 1)),
    referenceAt: referenceAt,
    title: 'Add parent-child navigation in item cards',
    message: overdue ? 'Overdue by 1 hour' : 'Due in 1 hour',
    isOverdue: overdue,
  );
}

class _FakeBiometricQuickUnlockService implements BiometricQuickUnlockService {
  _FakeBiometricQuickUnlockService({
    this.enabledForSession = false,
  });

  bool enabledForSession;
  String? _trustedUserId;

  @override
  Future<bool> canOffer(AuthSession session) async {
    return !enabledForSession;
  }

  @override
  Future<void> clear() async {
    enabledForSession = false;
    _trustedUserId = null;
  }

  @override
  Future<void> enableForSession(AuthSession session) async {
    enabledForSession = true;
    _trustedUserId = session.user.uid;
  }

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<void> markTrusted(AuthSession session) async {
    _trustedUserId = session.user.uid;
  }

  @override
  Future<bool> requiresUnlock(AuthSession session) async {
    return enabledForSession && _trustedUserId != session.user.uid;
  }

  @override
  Future<bool> unlock(AuthSession session) async {
    _trustedUserId = session.user.uid;
    return true;
  }
}

class _FailingAccountDataCleanupService implements AccountDataCleanupService {
  var callCount = 0;

  @override
  Future<void> deleteCloudData({required String userId}) async {
    callCount += 1;
    throw StateError('cloud cleanup failed');
  }
}

class _RecordingAccountDataCleanupService implements AccountDataCleanupService {
  var callCount = 0;

  @override
  Future<void> deleteCloudData({required String userId}) async {
    callCount += 1;
  }
}

class _FailingAccountDeletionPreflightService
    implements AccountDeletionPreflightService {
  @override
  Future<void> requireRecentAuthentication() async {
    throw StateError('recent authentication required');
  }
}

void main() {
  testWidgets('PlanDone app shows auth flow when unauthenticated',
      (WidgetTester tester) async {
    final container = _createTestContainer(null);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Sign in to PlanDone'), findsOneWidget);
    if (useFirebaseAuth) {
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);
      expect(find.textContaining('Local runtime profile'), findsNothing);
    } else {
      expect(find.text('Open local demo workspace'), findsOneWidget);
      expect(find.text('Forgot password?'), findsNothing);
      expect(find.textContaining('Local runtime profile'), findsOneWidget);
    }
    expect(find.byTooltip('Sync now'), findsNothing);

    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();

    expect(find.text('Create your PlanDone account'), findsOneWidget);
    expect(find.text('Display name'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
  });

  testWidgets('PlanDone app renders board shell for authenticated session',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    expect(find.text('Workspace'), findsWidgets);
    expect(find.byTooltip('Workspace tools'), findsOneWidget);
    expect(find.byTooltip('Search items'), findsOneWidget);
    expect(find.byTooltip('Reminders'), findsOneWidget);
    expect(find.text('Capture'), findsOneWidget);
    expect(find.byIcon(Icons.view_list_outlined), findsOneWidget);
    expect(find.byTooltip('Workspace view: Kanban'), findsOneWidget);
    expect(find.byIcon(Icons.filter_list), findsOneWidget);
    expect(find.text('Add Item'), findsOneWidget);
    expect(find.byTooltip('Sync now'), findsNothing);
    expect(find.byTooltip('Sign out'), findsNothing);
    expect(container.read(boardCardDensityProvider), BoardCardDensity.compact);

    await tester.tap(find.byTooltip('Workspace tools'));
    await tester.pumpAndSettle();

    expect(find.text('Workspace tools'), findsOneWidget);
    expect(find.text('Open inbox'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('kanban column headers keep only reorder controls',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Column semantics'), findsNothing);
    expect(find.byTooltip('Rename column'), findsNothing);
    expect(find.byTooltip('Delete column'), findsNothing);
    expect(find.byTooltip('Move first column right'), findsNothing);
    expect(find.byTooltip('Move left'), findsWidgets);
    expect(find.byTooltip('Move right'), findsWidgets);
  });

  testWidgets('biometric guard blocks an enabled session until unlocked',
      (WidgetTester tester) async {
    final biometricService = _FakeBiometricQuickUnlockService(
      enabledForSession: true,
    );
    final container = _createTestContainer(
      _signedInSession,
      overrides: [
        biometricQuickUnlockServiceProvider.overrideWithValue(biometricService),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    expect(find.text('Unlock PlanDone'), findsOneWidget);
    expect(find.text('Unlock with fingerprint'), findsWidgets);

    await tester.tap(find.text('Unlock with fingerprint').last);
    await tester.pumpAndSettle();

    expect(find.text('Unlock PlanDone'), findsNothing);
    expect(find.text('Workspace'), findsWidgets);
  });

  testWidgets('primary navigation switches between workspace routes',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();
    final flowItem = await container.read(boardControllerProvider).createItem(
          title: 'Flow nav item',
          type: WorkItemType.action,
          toColumnId: 'c-todo',
          dueAt: DateTime(2026, 3, 19),
        );
    await tester.pumpAndSettle();

    expect(find.text('Workspace'), findsWidgets);
    expect(_bottomNavLabel('Planning'), findsNothing);
    expect(_bottomNavLabel('Flow'), findsOneWidget);

    await tester.tap(_bottomNavLabel('Flow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Filters'), findsOneWidget);
    expect(
        find.byKey(ValueKey('flow-card-${flowItem.itemId}')), findsOneWidget);

    final configurationNavTarget =
        find.byType(NavigationRail).evaluate().isNotEmpty
            ? _railLabel('Configuration')
            : _bottomNavLabel('Configuration');
    await tester.tap(configurationNavTarget);
    await tester.pumpAndSettle();
    expect(find.text('Board Configuration'), findsOneWidget);
    expect(find.text('Board Scope'), findsOneWidget);
    expect(find.text('Default Workspace View'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Account'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);

    await tester.tap(_bottomNavLabel('Insights'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Accomplished'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Accomplished'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Board health'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Board health'), findsOneWidget);

    await tester.tap(_bottomNavLabel('Workspace'));
    await tester.pumpAndSettle();
    expect(find.text('Add Item'), findsOneWidget);
    expect(
      container.read(boardPlanningViewProvider),
      BoardPlanningView.kanban,
    );

    await tester.tap(_bottomNavLabel('Workspace'));
    await tester.pumpAndSettle();
    expect(
      container.read(boardPlanningViewProvider),
      BoardPlanningView.hierarchy,
    );
    expect(find.byTooltip('Workspace view: Hierarchy'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.account_tree),
      ),
      findsOneWidget,
    );

    await tester.tap(_bottomNavLabel('Workspace'));
    await tester.pumpAndSettle();
    expect(
      container.read(boardPlanningViewProvider),
      BoardPlanningView.calendar,
    );
  });

  testWidgets('flow exposes a persistent new-item puck with creation targets',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await tester.tap(_bottomNavLabel('Flow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final puck = find.byKey(const ValueKey('flow-create-puck'));
    expect(puck, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(puck));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(100, -120));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
        find.byKey(const ValueKey('flow-create-target-task')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('flow-create-target-capture')),
      findsOneWidget,
    );

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('top bar help action appears on all primary pages',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Help mode'), findsOneWidget);

    await tester.tap(_bottomNavLabel('Flow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byTooltip('Help mode'), findsOneWidget);

    await tester.tap(_bottomNavLabel('Insights'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Help mode'), findsOneWidget);

    final configurationNavTarget =
        find.byType(NavigationRail).evaluate().isNotEmpty
            ? _railLabel('Configuration')
            : _bottomNavLabel('Configuration');
    await tester.tap(configurationNavTarget);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Help mode'), findsOneWidget);
  });

  testWidgets('help mode opens contextual sheet for workspace targets',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Open configuration'), findsNothing);

    await tester.tap(find.byTooltip('Help mode').first);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Exit Help mode'), findsOneWidget);
    expect(
      find.byKey(
        ValueKey('help-target-${AppHelpTargetIds.workspaceCapture.key}'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey('help-target-${AppHelpTargetIds.workspaceBoardScope.key}'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey('help-target-${AppHelpTargetIds.workspaceFilters.key}'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey('help-target-${AppHelpTargetIds.workspaceTopFocus.key}'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey('help-target-${AppHelpTargetIds.workspaceTopTools.key}'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        ValueKey(
          'help-target-${AppHelpTargetIds.workspaceBoardScope.key}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Board scope'), findsOneWidget);
    expect(find.text('When to use it'), findsOneWidget);
    expect(find.text('What happens'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Close'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Exit Help mode'), findsOneWidget);
  });

  testWidgets('hierarchy view exposes branch-specific help targets',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await tester.tap(_bottomNavLabel('Workspace'));
    await tester.pumpAndSettle();
    expect(
      container.read(boardPlanningViewProvider),
      BoardPlanningView.hierarchy,
    );

    await tester.tap(find.byTooltip('Help mode').first);
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        ValueKey(
            'help-target-${AppHelpTargetIds.workspaceHierarchyControls.key}'),
      ),
      findsOneWidget,
    );

    expect(find.byTooltip('Exit Help mode'), findsOneWidget);
  });

  testWidgets(
      'configuration help toggles floating button and replays Flow walkthrough',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    final configurationNavTarget =
        find.byType(NavigationRail).evaluate().isNotEmpty
            ? _railLabel('Configuration')
            : _bottomNavLabel('Configuration');
    await tester.tap(configurationNavTarget);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Floating help button'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.byTooltip('Help mode'), findsOneWidget);

    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Help mode'), findsNWidgets(2));

    await tester.tap(find.text('Replay Flow walkthrough'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Flow walkthrough'), findsOneWidget);
    expect(find.text('Set the lane you are sorting'), findsOneWidget);
  });

  testWidgets('calendar walkthrough changes view state step by step',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    container.read(boardControllerProvider).setPlanningView(
          BoardPlanningView.calendar,
        );
    await tester.pumpAndSettle();

    await container.read(appHelpControllerProvider).startTour(
          AppHelpTourId.calendar,
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(boardCalendarSubviewProvider),
        BoardCalendarSubview.month);
    expect(container.read(boardCalendarShowUnscheduledProvider), isFalse);

    await container.read(appHelpControllerProvider).advanceTour();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      container.read(boardCalendarSubviewProvider),
      BoardCalendarSubview.week,
    );

    await container.read(appHelpControllerProvider).advanceTour();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(boardCalendarShowUnscheduledProvider), isTrue);
    expect(find.byKey(const ValueKey('calendar-unscheduled-tray')),
        findsOneWidget);
  });

  testWidgets('workspace walkthrough reveals filters and search in place',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await container.read(appHelpControllerProvider).startTour(
          AppHelpTourId.workspace,
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(boardPlanningViewProvider), BoardPlanningView.kanban);
    expect(container.read(boardVisibilityFilterProvider), isEmpty);
    expect(container.read(workspaceSearchExpandedProvider), isFalse);

    await container.read(appHelpControllerProvider).advanceTour();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await container.read(appHelpControllerProvider).advanceTour();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await container.read(appHelpControllerProvider).advanceTour();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      container.read(boardVisibilityFilterProvider),
      <WorkItemType>{WorkItemType.task, WorkItemType.action},
    );
    expect(container.read(showDueSoonOnlyProvider), isTrue);

    await container.read(appHelpControllerProvider).advanceTour();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await container.read(appHelpControllerProvider).advanceTour();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(workspaceSearchExpandedProvider), isTrue);
    expect(find.byType(TextFormField), findsOneWidget);
  });

  testWidgets('hierarchy walkthrough selects and expands a real branch',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    final parent = await container.read(boardControllerProvider).createItem(
          title: 'Tour parent',
          type: WorkItemType.goal,
          toColumnId: 'c-todo',
        );
    await container.read(boardControllerProvider).createItem(
          title: 'Tour child',
          type: WorkItemType.task,
          toColumnId: 'c-todo',
          parentId: parent.itemId,
        );
    await tester.pumpAndSettle();

    await container.read(appHelpControllerProvider).startTour(
          AppHelpTourId.hierarchy,
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      container.read(boardPlanningViewProvider),
      BoardPlanningView.hierarchy,
    );
    expect(container.read(selectedHierarchyItemIdProvider), isNotNull);

    final initiallyCollapsed =
        container.read(collapsedHierarchyItemIdsProvider);
    expect(initiallyCollapsed.length, lessThanOrEqualTo(1));

    await container.read(appHelpControllerProvider).advanceTour();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(collapsedHierarchyItemIdsProvider), isEmpty);
  });

  testWidgets('flow walkthrough exposes the decision ring step',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();
    await container.read(boardControllerProvider).createItem(
          title: 'Flow walkthrough item',
          type: WorkItemType.action,
          toColumnId: 'c-todo',
          dueAt: DateTime(2026, 3, 19),
        );
    await tester.pumpAndSettle();

    await tester.tap(_bottomNavLabel('Flow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await container.read(appHelpControllerProvider).startTour(
          AppHelpTourId.flow,
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      container.read(boardFlowVisibleTypesProvider),
      const {WorkItemType.action},
    );

    await container.read(appHelpControllerProvider).advanceTour();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await container.read(appHelpControllerProvider).advanceTour();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const ValueKey('flow-target-do-now')), findsOneWidget);
    expect(find.text('Flow walkthrough'), findsOneWidget);
  });

  testWidgets('flow defaults to actions-only and can add tasks through filters',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    final actionItem = await container.read(boardControllerProvider).createItem(
          title: 'Flow action default',
          type: WorkItemType.action,
          toColumnId: 'c-todo',
        );
    final taskItem = await container.read(boardControllerProvider).createItem(
          title: 'Flow task opt-in',
          type: WorkItemType.task,
          toColumnId: 'c-todo',
        );
    await tester.pumpAndSettle();

    await tester.tap(_bottomNavLabel('Flow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
        container.read(boardFlowVisibleTypesProvider), {WorkItemType.action});
    expect(find.text('7D'), findsNothing);
    var snapshot = container.read(boardFlowSnapshotProvider).valueOrNull!;
    expect(
      snapshot.candidates.map((entry) => entry.item.itemId),
      contains(actionItem.itemId),
    );
    expect(
      snapshot.candidates.map((entry) => entry.item.itemId),
      isNot(contains(taskItem.itemId)),
    );

    await tester.tap(find.text('Filters'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Task'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      container.read(boardFlowVisibleTypesProvider),
      {WorkItemType.action, WorkItemType.task},
    );
    snapshot = container.read(boardFlowSnapshotProvider).valueOrNull!;
    expect(
      snapshot.candidates.map((entry) => entry.item.itemId),
      contains(taskItem.itemId),
    );
  });

  testWidgets('flow suppression removes a card from the playfield',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();
    final flowItem = await container.read(boardControllerProvider).createItem(
          title: 'Flow dismiss item',
          type: WorkItemType.action,
          toColumnId: 'c-todo',
          dueAt: DateTime(2026, 3, 19),
        );
    await tester.pumpAndSettle();

    await tester.tap(_bottomNavLabel('Flow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await container.read(boardControllerProvider).setFlowMotionEnabled(false);
    await tester.pump(const Duration(milliseconds: 50));

    final cardFinder = find.byKey(ValueKey('flow-card-${flowItem.itemId}'));
    expect(cardFinder, findsOneWidget);
    final candidate = container
        .read(boardFlowSnapshotProvider)
        .valueOrNull!
        .candidates
        .firstWhere((entry) => entry.item.itemId == flowItem.itemId);
    await container
        .read(boardControllerProvider)
        .suppressFlowItemUntilTomorrowMorning(
          item: flowItem,
          stateToken: candidate.stateToken,
        );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(ValueKey('flow-card-${flowItem.itemId}')), findsNothing);
  });

  testWidgets('flow motion chip pauses motion preference',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await tester.tap(_bottomNavLabel('Flow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(container.read(boardFlowMotionEnabledProvider), isTrue);

    final motionChip = find.ancestor(
      of: find.text('Motion on'),
      matching: find.byType(RawChip),
    );
    await tester.tap(motionChip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(boardFlowMotionEnabledProvider), isFalse);
    expect(find.text('Paused'), findsOneWidget);
  });

  testWidgets('flow filters slider updates motion speed preference',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await tester.tap(_bottomNavLabel('Flow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      container.read(boardFlowMotionSpeedProvider),
      boardFlowDefaultMotionSpeed,
    );

    await tester.tap(find.text('Filters'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final slider = find.byKey(const ValueKey('flow-speed-slider'));
    expect(slider, findsOneWidget);
    final sliderWidget = tester.widget<Slider>(slider);
    sliderWidget.onChanged!(1.5);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      container.read(boardFlowMotionSpeedProvider),
      greaterThan(boardFlowDefaultMotionSpeed),
    );
  });

  testWidgets('flow mallet still appears while motion is paused',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await container.read(boardControllerProvider).createItem(
          title: 'Flow mallet action',
          type: WorkItemType.action,
          toColumnId: 'c-todo',
        );
    await tester.pumpAndSettle();

    await tester.tap(_bottomNavLabel('Flow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await container.read(boardControllerProvider).setFlowMotionEnabled(false);
    await tester.pump(const Duration(milliseconds: 50));

    final playfield = find.byKey(const ValueKey('flow-playfield'));
    final gesture = await tester.startGesture(
      tester.getTopLeft(playfield) + const Offset(32, 32),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('flow-mallet')), findsOneWidget);

    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
  });

  testWidgets('configuration account delete flow requires typed confirmation',
      (WidgetTester tester) async {
    final biometricService = _FakeBiometricQuickUnlockService();
    final container = _createTestContainer(
      _signedInSession,
      overrides: [
        biometricQuickUnlockServiceProvider.overrideWithValue(biometricService),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    final configurationNavTarget =
        find.byType(NavigationRail).evaluate().isNotEmpty
            ? _railLabel('Configuration')
            : _bottomNavLabel('Configuration');
    await tester.tap(configurationNavTarget);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Fingerprint quick unlock'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Fingerprint quick unlock'), findsOneWidget);

    final deleteAccountTile = find.ancestor(
      of: find.text('Delete account'),
      matching: find.byType(ListTile),
    );
    await tester.scrollUntilVisible(
      deleteAccountTile,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(deleteAccountTile);
    await tester.pumpAndSettle();

    expect(find.text('Delete account permanently?'), findsOneWidget);
    expect(find.text('Type DELETE to continue.'), findsOneWidget);

    final deleteButton = find.widgetWithText(FilledButton, 'Delete account');
    expect(tester.widget<FilledButton>(deleteButton).onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, 'DELETE');
    await tester.pump();

    expect(tester.widget<FilledButton>(deleteButton).onPressed, isNotNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Delete account permanently?'), findsNothing);
  });

  test('account deletion keeps authentication when cloud cleanup fails',
      () async {
    final cleanupService = _FailingAccountDataCleanupService();
    final container = _createTestContainer(
      _signedInSession,
      overrides: [
        accountDataCleanupServiceProvider.overrideWithValue(cleanupService),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authSessionProvider.future);

    await expectLater(
      container
          .read(accountManagementControllerProvider)
          .deleteCurrentAccount(),
      throwsStateError,
    );

    expect(cleanupService.callCount, 1);
    final session =
        await container.read(authRepositoryProvider).authStateChanges().first;
    expect(session?.user.uid, _signedInSession.user.uid);
  });

  test('account deletion does not clean cloud data when preflight fails',
      () async {
    final cleanupService = _RecordingAccountDataCleanupService();
    final container = _createTestContainer(
      _signedInSession,
      overrides: [
        accountDeletionPreflightServiceProvider.overrideWithValue(
          _FailingAccountDeletionPreflightService(),
        ),
        accountDataCleanupServiceProvider.overrideWithValue(cleanupService),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authSessionProvider.future);

    await expectLater(
      container
          .read(accountManagementControllerProvider)
          .deleteCurrentAccount(),
      throwsStateError,
    );

    expect(cleanupService.callCount, 0);
    final session =
        await container.read(authRepositoryProvider).authStateChanges().first;
    expect(session?.user.uid, _signedInSession.user.uid);
  });

  testWidgets('active workspace tap cycles views on navigation rail too',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(_railLabel('Planning'), findsNothing);

    await tester.tap(_railLabel('Workspace'));
    await tester.pumpAndSettle();

    expect(
      container.read(boardPlanningViewProvider),
      BoardPlanningView.hierarchy,
    );
  });

  testWidgets(
      'configuration exposes column visibility and manual add defaults to visible',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    final configurationNavTarget =
        find.byType(NavigationRail).evaluate().isNotEmpty
            ? _railLabel('Configuration')
            : _bottomNavLabel('Configuration');
    await tester.tap(configurationNavTarget);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byTooltip('Add column'),
      160,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.byTooltip('Add column'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is DropdownButtonFormField,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blocked').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    var snapshot = container.read(boardStreamProvider).valueOrNull!;
    var blockedColumn =
        snapshot.columns.firstWhere((column) => column.name == 'Blocked');
    expect(blockedColumn.isEnabled, isTrue);
    expect(find.textContaining('Visible'), findsWidgets);

    await container.read(boardControllerProvider).updateColumnSemantics(
          columnId: blockedColumn.columnId,
          isEnabled: false,
        );
    await tester.pumpAndSettle();

    snapshot = container.read(boardStreamProvider).valueOrNull!;
    blockedColumn =
        snapshot.columns.firstWhere((column) => column.name == 'Blocked');
    expect(blockedColumn.isEnabled, isFalse);
    expect(find.textContaining('Hidden'), findsWidgets);
  });

  testWidgets('insights page shows board metrics and reacts to range changes',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Insights'));
    await tester.pumpAndSettle();

    expect(find.text('My Board'), findsOneWidget);
    expect(find.text('Suggested next read'), findsOneWidget);
    expect(find.text('Today & next'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Accomplished'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Accomplished'), findsOneWidget);
    expect(find.text('Completed total'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Momentum'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Momentum'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Work shape'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Work shape'), findsOneWidget);
    expect(find.text('Pressure points'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Board health'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Board health'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Attention'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Attention'), findsOneWidget);

    container.read(selectedBoardInsightsRangeProvider.notifier).state =
        BoardInsightsRange.allTime;
    await tester.pumpAndSettle();

    expect(
      container.read(selectedBoardInsightsRangeProvider),
      BoardInsightsRange.allTime,
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, 1200));
    await tester.pumpAndSettle();
    expect(
      find.text('Board-neutral progress and execution health for all time.'),
      findsOneWidget,
    );
  });

  testWidgets('insights view exposes section-specific help targets',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await tester.tap(_bottomNavLabel('Insights'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Help mode').first);
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        ValueKey('help-target-${AppHelpTargetIds.insightsHeader.key}'),
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Accomplished'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(
        ValueKey('help-target-${AppHelpTargetIds.insightsAccomplished.key}'),
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Momentum'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(
        ValueKey('help-target-${AppHelpTargetIds.insightsMomentum.key}'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('workspace type filter supports multi-select chips',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    expect(
      container.read(boardVisibilityFilterProvider),
      {WorkItemType.task},
    );

    final filterButton = find
        .ancestor(
          of: find.byIcon(Icons.filter_list).first,
          matching: find.byType(InkWell),
        )
        .first;
    await tester.ensureVisible(filterButton);
    await tester.tap(filterButton);
    await tester.pumpAndSettle();

    expect(find.text('View'), findsOneWidget);
    await tester.tap(find.byTooltip('Focus').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Goals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(
      container.read(boardPlanningViewProvider),
      BoardPlanningView.focus,
    );
    expect(
      container.read(boardVisibilityFilterProvider),
      {WorkItemType.task, WorkItemType.goal},
    );
  });

  testWidgets('workspace all boards scope renders columns from other boards',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await container.read(boardControllerProvider).createBoard('Ops Board');
    final secondBoardId = container.read(currentBoardIdProvider);
    await container.read(boardControllerProvider).createColumn('Review');
    container.read(workspaceSelectedBoardIdsProvider.notifier).state = {};
    await tester.pumpAndSettle();

    expect(container.read(currentBoardIdProvider), secondBoardId);
    await tester.pumpAndSettle();
    expect(find.text('To Do'), findsOneWidget);
    expect(find.text('Doing'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);

    final todoLaneContainer = tester.widget<Container>(
      find.byKey(
        const ValueKey('multi-board-kanban-lane-content-To Do'),
      ),
    );
    final todoLaneDecoration = todoLaneContainer.decoration as BoxDecoration;
    expect(todoLaneDecoration.border, isNull);
  });

  testWidgets('switching to a created board keeps the active board stream live',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await container.read(boardControllerProvider).createBoard('Ops Board');
    final secondBoardId = container.read(currentBoardIdProvider);

    container.read(boardControllerProvider).switchBoard(defaultBoardId);
    await tester.pumpAndSettle();

    container.read(boardControllerProvider).switchBoard(secondBoardId);
    await tester.pumpAndSettle();

    expect(
      container.read(boardStreamProvider).valueOrNull?.board.boardId,
      secondBoardId,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('workspace view chip opens direct picker and updates quick views',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Workspace view: Kanban'));
    await tester.pumpAndSettle();

    expect(find.text('Workspace view'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Focus'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Backlog'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Calendar'));
    await tester.pumpAndSettle();

    expect(
      container.read(boardPlanningViewProvider),
      BoardPlanningView.calendar,
    );
    expect(find.byTooltip('Workspace view: Calendar'), findsOneWidget);
  });

  testWidgets('focus view is available from the top app bar action',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Focus view'));
    await tester.pumpAndSettle();

    expect(
      container.read(boardPlanningViewProvider),
      BoardPlanningView.focus,
    );
  });

  testWidgets('calendar view restores last used subview and visible date kinds',
      (WidgetTester tester) async {
    final sharedCalendarRepo = InMemoryBoardCalendarPreferencesRepository(
      userId: _signedInSession.user.uid,
    );
    final container = _createTestContainer(
      _signedInSession,
      overrides: [
        boardCalendarPreferencesRepositoryProvider.overrideWithValue(
          sharedCalendarRepo,
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Workspace view: Kanban'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Calendar'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Week'));
    await tester.pumpAndSettle();
    final filtersButton = find.descendant(
      of: find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip && ((widget.message ?? '').startsWith('Filters')),
      ),
      matching: find.byType(InkWell),
    );
    expect(filtersButton, findsOneWidget);
    await tester.tap(filtersButton);
    await tester.pumpAndSettle();
    final filtersSheet = find.byType(BottomSheet);
    final dueChip = find.descendant(
      of: filtersSheet,
      matching: find.widgetWithText(FilterChip, 'Due'),
    );
    await tester.ensureVisible(dueChip);
    await tester.tap(
      dueChip,
    );
    await tester.pumpAndSettle();
    final applyButton = find.descendant(
      of: filtersSheet,
      matching: find.widgetWithText(FilledButton, 'Apply'),
    );
    await tester.ensureVisible(applyButton);
    await tester.tap(
      applyButton,
    );
    await tester.pumpAndSettle();

    expect(
      container.read(boardCalendarSubviewProvider),
      BoardCalendarSubview.week,
    );
    expect(
      container
          .read(boardCalendarVisibleDateKindsProvider)
          .contains(BoardCalendarMarkerKind.due),
      isFalse,
    );
    final saved = await sharedCalendarRepo.load();
    expect(
      saved.lastSubview,
      BoardCalendarSubview.week,
    );
    expect(
      saved.visibleDateKinds.contains(BoardCalendarMarkerKind.due),
      isFalse,
    );
  });

  testWidgets('calendar day view filters placements by selected date kind',
      (WidgetTester tester) async {
    final calendarRepo = InMemoryBoardCalendarPreferencesRepository(
      userId: 'calendar-filter-user',
    );
    final container = _createTestContainer(
      _signedInSession,
      overrides: [
        boardCalendarPreferencesRepositoryProvider.overrideWithValue(
          calendarRepo,
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    container.read(boardVisibilityFilterProvider.notifier).state =
        <WorkItemType>{};
    await container.read(boardControllerProvider).updateItem(
          itemId: 'a-3',
          startAt: DateTime(2026, 3, 20),
          targetEndAt: DateTime(2026, 3, 20),
          dueAt: DateTime(2026, 3, 20),
        );
    await container
        .read(boardControllerProvider)
        .setCalendarSubview(BoardCalendarSubview.day);
    await container.read(boardControllerProvider).setCalendarVisibleDateKinds(
      {
        BoardCalendarMarkerKind.start,
        BoardCalendarMarkerKind.targetEnd,
        BoardCalendarMarkerKind.due,
      },
    );
    container
        .read(boardControllerProvider)
        .setCalendarAnchorDate(DateTime(2026, 3, 20));
    container
        .read(boardControllerProvider)
        .setPlanningView(BoardPlanningView.calendar);
    await tester.pumpAndSettle();

    final titleFinder = find.text('Add parent-child navigation in item cards');
    expect(titleFinder, findsNWidgets(3));

    final filtersButton = find.descendant(
      of: find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip && ((widget.message ?? '').startsWith('Filters')),
      ),
      matching: find.byType(InkWell),
    );
    expect(filtersButton, findsOneWidget);
    await tester.tap(filtersButton);
    await tester.pumpAndSettle();
    final filtersSheet = find.byType(BottomSheet);
    final dueChip = find.descendant(
      of: filtersSheet,
      matching: find.widgetWithText(FilterChip, 'Due'),
    );
    await tester.ensureVisible(dueChip);
    await tester.tap(
      dueChip,
    );
    await tester.pumpAndSettle();
    final applyButton = find.descendant(
      of: filtersSheet,
      matching: find.widgetWithText(FilledButton, 'Apply'),
    );
    await tester.ensureVisible(applyButton);
    await tester.tap(
      applyButton,
    );
    await tester.pumpAndSettle();

    expect(titleFinder, findsNWidgets(2));
  });

  testWidgets('calendar swipe gestures navigate month, week, and day ranges',
      (WidgetTester tester) async {
    final calendarRepo = InMemoryBoardCalendarPreferencesRepository(
      userId: 'calendar-swipe-user',
    );
    final container = _createTestContainer(
      _signedInSession,
      overrides: [
        boardCalendarPreferencesRepositoryProvider.overrideWithValue(
          calendarRepo,
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    container
        .read(boardControllerProvider)
        .setPlanningView(BoardPlanningView.calendar);
    await tester.pumpAndSettle();

    container
        .read(boardControllerProvider)
        .setCalendarAnchorDate(DateTime(2026, 3, 19));
    await tester.pumpAndSettle();
    expect(find.text('March 2026'), findsOneWidget);

    Future<void> swipeCalendar(Offset delta) async {
      final swipeRect =
          tester.getRect(find.byKey(const ValueKey('calendar-swipe-surface')));
      final gesture = await tester.startGesture(swipeRect.center);
      await gesture.moveBy(delta);
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await swipeCalendar(const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(find.text('April 2026'), findsOneWidget);

    await swipeCalendar(const Offset(240, 0));
    expect(find.text('March 2026'), findsOneWidget);

    await container
        .read(boardControllerProvider)
        .setCalendarSubview(BoardCalendarSubview.week);
    container
        .read(boardControllerProvider)
        .setCalendarAnchorDate(DateTime(2026, 3, 19));
    await tester.pumpAndSettle();
    expect(find.text('Mar 16 - Mar 22, 2026'), findsOneWidget);

    await swipeCalendar(const Offset(-240, 0));
    expect(find.text('Mar 23 - Mar 29, 2026'), findsOneWidget);

    await container
        .read(boardControllerProvider)
        .setCalendarSubview(BoardCalendarSubview.day);
    container
        .read(boardControllerProvider)
        .setCalendarAnchorDate(DateTime(2026, 3, 19));
    await tester.pumpAndSettle();
    expect(find.text('March 19, 2026'), findsOneWidget);

    await swipeCalendar(const Offset(-240, 0));
    expect(find.text('March 20, 2026'), findsOneWidget);
  });

  testWidgets('calendar shows unscheduled items in a bottom tray',
      (WidgetTester tester) async {
    final calendarRepo = InMemoryBoardCalendarPreferencesRepository(
      userId: 'calendar-unscheduled-user',
    );
    final container = _createTestContainer(
      _signedInSession,
      overrides: [
        boardCalendarPreferencesRepositoryProvider.overrideWithValue(
          calendarRepo,
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await container.read(boardControllerProvider).updateItem(
          itemId: 'a-4',
          clearStartAt: true,
          clearTargetEndAt: true,
          clearDueAt: true,
        );
    container
        .read(boardControllerProvider)
        .setPlanningView(BoardPlanningView.calendar);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('calendar-unscheduled-tray')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-unscheduled-tray-list')),
        findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('calendar-unscheduled-tray-toggle')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('calendar-unscheduled-tray-list')),
        findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Pick date'), findsWidgets);
  });

  testWidgets('month day agenda sheet scrolls when many items are scheduled',
      (WidgetTester tester) async {
    final calendarRepo = InMemoryBoardCalendarPreferencesRepository(
      userId: 'calendar-overflow-user',
    );
    final container = _createTestContainer(
      _signedInSession,
      overrides: [
        boardCalendarPreferencesRepositoryProvider.overrideWithValue(
          calendarRepo,
        ),
      ],
    );
    addTearDown(container.dispose);

    final boardSnapshot =
        await container.read(localBoardStoreProvider).getBoard('board-1');
    final templateItem =
        boardSnapshot.items.firstWhere((item) => item.itemId == 'a-3');
    for (var index = 0; index < 10; index++) {
      await container.read(localBoardStoreProvider).upsertItem(
            WorkItem(
              itemId: 'overflow-$index',
              boardId: templateItem.boardId,
              title: 'Overflow item $index',
              type: templateItem.type,
              columnId: templateItem.columnId,
              sortOrder: 1000.0 + index,
              parentId: templateItem.parentId,
              description: templateItem.description,
              assigneeIds: templateItem.assigneeIds,
              startAt: templateItem.startAt,
              targetEndAt: templateItem.targetEndAt,
              dueAt: DateTime(2026, 3, 20),
              completedAt: null,
              estimatedEffortMinutes: templateItem.estimatedEffortMinutes,
              actualEffortMinutes: templateItem.actualEffortMinutes,
              tags: templateItem.tags,
              archived: false,
              isInbox: false,
              recurrence: null,
              createdAt: DateTime(2026, 3, 19, 8, index),
              updatedAt: DateTime(2026, 3, 20, 8, index),
            ),
          );
    }

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    container
        .read(boardControllerProvider)
        .setPlanningView(BoardPlanningView.calendar);
    await container
        .read(boardControllerProvider)
        .setCalendarSubview(BoardCalendarSubview.month);
    container
        .read(boardControllerProvider)
        .setCalendarAnchorDate(DateTime(2026, 3, 20));
    await tester.pumpAndSettle();

    final monthDayLabel = find.descendant(
      of: find.byKey(const ValueKey('calendar-month-grid')),
      matching: find.text('20'),
    );
    final monthDayCell = find.ancestor(
      of: monthDayLabel,
      matching: find.byType(InkWell),
    );
    final monthDayInkWell = tester.widget<InkWell>(monthDayCell.first);
    monthDayInkWell.onTap!.call();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final scrollSurface =
        find.byKey(const ValueKey('calendar-day-agenda-sheet-scroll'));
    expect(scrollSurface, findsOneWidget);

    await tester.drag(scrollSurface, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.drag(scrollSurface, const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar drag to another date updates due date and stages undo',
      (WidgetTester tester) async {
    final calendarRepo = InMemoryBoardCalendarPreferencesRepository(
      userId: 'calendar-drag-user',
    );
    final container = _createTestContainer(
      _signedInSession,
      overrides: [
        boardCalendarPreferencesRepositoryProvider.overrideWithValue(
          calendarRepo,
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    container.read(boardVisibilityFilterProvider.notifier).state =
        <WorkItemType>{};
    await container.read(boardControllerProvider).updateItem(
          itemId: 'a-4',
          dueAt: DateTime(2026, 3, 19),
          clearStartAt: true,
          clearTargetEndAt: true,
        );
    await container
        .read(boardControllerProvider)
        .setCalendarSubview(BoardCalendarSubview.week);
    await container.read(boardControllerProvider).setCalendarVisibleDateKinds(
      {
        BoardCalendarMarkerKind.start,
        BoardCalendarMarkerKind.targetEnd,
        BoardCalendarMarkerKind.due,
      },
    );
    container
        .read(boardControllerProvider)
        .setCalendarAnchorDate(DateTime(2026, 3, 19));
    container
        .read(boardControllerProvider)
        .setPlanningView(BoardPlanningView.calendar);
    await tester.pumpAndSettle();
    await container
        .read(boardControllerProvider)
        .setCalendarSubview(BoardCalendarSubview.week);
    container
        .read(boardControllerProvider)
        .setCalendarAnchorDate(DateTime(2026, 3, 19));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Workspace view: Calendar'), findsOneWidget);
    expect(container.read(boardCalendarSubviewProvider),
        BoardCalendarSubview.week);
    expect(find.text('Mar 16 - Mar 22, 2026'), findsOneWidget);
    final targetLabelFinder = find.descendant(
      of: find.byType(BoardCalendarView),
      matching: find.text('Wednesday, Mar 18'),
    );
    final targetFinder = find
        .ancestor(
          of: targetLabelFinder,
          matching: find.byWidgetPredicate(
            (widget) => widget is DragTarget<WorkItem>,
          ),
        )
        .first;
    expect(targetLabelFinder, findsOneWidget);

    final item = container
        .read(boardStreamProvider)
        .valueOrNull!
        .items
        .firstWhere((entry) => entry.itemId == 'a-4');
    final targetWidget = tester.widget<DragTarget<WorkItem>>(targetFinder);
    targetWidget.onAcceptWithDetails?.call(
      DragTargetDetails<WorkItem>(
        data: item,
        offset: tester.getCenter(targetLabelFinder),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump();

    final updatedItem = container
        .read(boardStreamProvider)
        .valueOrNull!
        .items
        .firstWhere((entry) => entry.itemId == 'a-4');
    expect(updatedItem.dueAt, DateTime(2026, 3, 18));
  });

  test('stageDueDateUndo stores a reschedule undo operation', () {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    final item = WorkItem(
      itemId: 'a-4',
      boardId: 'board-1',
      title: 'Create Drift schema for boards/columns/items',
      type: WorkItemType.action,
      columnId: 'c-doing',
      createdAt: DateTime(2026, 3, 19, 9),
      updatedAt: DateTime(2026, 3, 19, 9),
      dueAt: DateTime(2026, 3, 19),
    );

    container.read(boardControllerProvider).stageDueDateUndo(
          item: item,
          fromDueAt: DateTime(2026, 3, 19),
          toDueAt: DateTime(2026, 3, 18),
        );

    final pendingUndo = container.read(pendingBoardUndoOperationProvider);
    expect(pendingUndo, isNotNull);
    expect(pendingUndo!.kind, BoardUndoOperationKind.rescheduleDueDate);
    expect(pendingUndo.fromDueAt, DateTime(2026, 3, 19));
    expect(pendingUndo.toDueAt, DateTime(2026, 3, 18));
  });

  testWidgets('planning route redirects into workspace',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    final navigator = Navigator.of(tester.element(find.byType(Scaffold).first));
    navigator.pushReplacementNamed(AppRoutes.planning);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Add Item'), findsOneWidget);
    expect(find.text('Planning Entry Point'), findsNothing);
  });

  testWidgets('view details sheet renders refreshed sections',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await container.read(boardControllerProvider).updateItem(
      itemId: 'g-1',
      description:
          'Deliver the first personal MVP with a planning-first workflow.',
      dueAt: DateTime(2026, 3, 20),
      estimatedEffortMinutes: 240,
      tags: const ['mvp', 'planning'],
    );
    await tester.pumpAndSettle();

    final snapshot = container.read(boardStreamProvider).valueOrNull!;
    final item = snapshot.items.firstWhere((entry) => entry.itemId == 'g-1');
    final columnName = snapshot.columns
        .firstWhere((entry) => entry.columnId == item.columnId)
        .name;

    container
        .read(boardControllerProvider)
        .setPlanningView(BoardPlanningView.hierarchy);
    await tester.pumpAndSettle();

    final itemCardFinder = find
        .ancestor(
          of: find.text('Ship PlanDone MVP').first,
          matching: find.byType(Card),
        )
        .first;
    final popupButtonFinder = find.descendant(
      of: itemCardFinder,
      matching: find.byType(PopupMenuButton<String>),
    );

    tester
        .state<PopupMenuButtonState<String>>(popupButtonFinder)
        .showButtonMenu();
    await tester.pumpAndSettle();
    await tester.tap(find.text('View details'));
    await tester.pumpAndSettle();

    expect(find.text('Quick facts'), findsOneWidget);
    expect(find.text('Goal'), findsOneWidget);
    expect(find.text(columnName), findsOneWidget);
    expect(find.textContaining(item.updatedAt.toLocal().toIso8601String()),
        findsNothing);
    final detailsList = find.byType(ListView).last;
    await tester.drag(detailsList, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(find.text('Description'), findsOneWidget);
    expect(
        find.text(
            'Deliver the first personal MVP with a planning-first workflow.'),
        findsOneWidget);
    await tester.drag(detailsList, const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(find.text('Context'), findsOneWidget);
    await tester.drag(detailsList, const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(find.text('Activity'), findsOneWidget);
  });

  testWidgets('details view respects metadata visibility settings',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    final initialSnapshot = container.read(boardStreamProvider).valueOrNull!;
    await container.read(boardControllerProvider).updateBoardValidationSettings(
          initialSnapshot.board.validationSettings.copyWith(
            showCreatedDate: false,
            showEstimatedEffort: false,
          ),
        );
    await container.read(boardControllerProvider).updateItem(
          itemId: 'g-1',
          estimatedEffortMinutes: 180,
        );
    await tester.pumpAndSettle();

    container
        .read(boardControllerProvider)
        .setPlanningView(BoardPlanningView.hierarchy);
    await tester.pumpAndSettle();

    final itemCardFinder = find
        .ancestor(
          of: find.text('Ship PlanDone MVP').first,
          matching: find.byType(Card),
        )
        .first;
    final popupButtonFinder = find.descendant(
      of: itemCardFinder,
      matching: find.byType(PopupMenuButton<String>),
    );
    tester
        .state<PopupMenuButtonState<String>>(popupButtonFinder)
        .showButtonMenu();
    await tester.pumpAndSettle();
    await tester.tap(find.text('View details'));
    await tester.pumpAndSettle();

    expect(find.text('Created'), findsNothing);
    expect(find.text('Estimate'), findsNothing);
  });

  testWidgets(
      'double-tap details sheet shows inline status chips and moves item',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    final taskFinder = find.text('Implement hierarchy and filtering behavior');
    await tester.tap(taskFinder);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(taskFinder);
    await tester.pumpAndSettle();

    expect(find.text('Status'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('item-details-status-row')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('item-status-chip-c-doing')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('item-status-chip-c-todo')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('item-status-chip-c-todo')));
    await tester.pumpAndSettle();

    final updatedItem = container
        .read(boardStreamProvider)
        .valueOrNull!
        .items
        .firstWhere((entry) => entry.itemId == 't-2');
    expect(updatedItem.columnId, 'c-todo');
  });

  testWidgets('details sheet keeps status passive for single-column boards',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await container.read(boardControllerProvider).createBoard('Lean Board');
    final leanBoardId = container.read(currentBoardIdProvider);
    final leanSnapshot =
        await container.read(localBoardStoreProvider).getBoard(leanBoardId);
    for (final column in leanSnapshot.columns) {
      if (column.columnId != '$leanBoardId-c-doing') {
        await container
            .read(boardControllerProvider)
            .deleteColumn(column.columnId);
      }
    }
    await container.read(boardControllerProvider).createItem(
          title: 'Lean Task',
          type: WorkItemType.task,
          toColumnId: '$leanBoardId-c-doing',
        );
    await tester.pumpAndSettle();

    final leanTaskFinder = find.text('Lean Task');
    await tester.tap(leanTaskFinder);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(leanTaskFinder);
    await tester.pumpAndSettle();

    expect(find.text('Status'), findsOneWidget);
    expect(find.byKey(const ValueKey('item-details-status-row')), findsNothing);
    expect(find.byKey(const ValueKey('item-status-chip-c-todo')), findsNothing);
  });

  testWidgets(
      'details sheet shows and updates status options for items from another visible board',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await container.read(boardControllerProvider).createBoard('Ops Board');
    final secondBoardId = container.read(currentBoardIdProvider);
    await container.read(boardControllerProvider).createColumn('Review');
    final secondBoardSnapshot =
        await container.read(localBoardStoreProvider).getBoard(secondBoardId);
    final reviewColumn = secondBoardSnapshot.columns.firstWhere(
      (column) => column.name == 'Review',
    );
    final created = await container.read(boardControllerProvider).createItem(
          title: 'Ops Task',
          type: WorkItemType.task,
          toColumnId: '$secondBoardId-c-doing',
        );

    container.read(boardControllerProvider).switchBoard(defaultBoardId);
    container.read(workspaceSelectedBoardIdsProvider.notifier).state = {};
    await tester.pumpAndSettle();

    final opsTaskFinder = find.text('Ops Task');
    await tester.tap(opsTaskFinder);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(opsTaskFinder);
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('item-details-status-row')), findsOneWidget);
    expect(
      find.byKey(ValueKey('item-status-chip-${reviewColumn.columnId}')),
      findsOneWidget,
    );

    await tester
        .tap(find.byKey(ValueKey('item-status-chip-${reviewColumn.columnId}')));
    await tester.pumpAndSettle();

    final updatedSnapshot =
        await container.read(localBoardStoreProvider).getBoard(secondBoardId);
    final updatedItem = updatedSnapshot.items.firstWhere(
      (entry) => entry.itemId == created.itemId,
    );
    expect(updatedItem.columnId, reviewColumn.columnId);
  });

  testWidgets('details sheet shows configured hidden columns in status choices',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await container.read(boardControllerProvider).createColumn('Blocked');
    final snapshot = container.read(boardStreamProvider).valueOrNull!;
    final blockedColumn =
        snapshot.columns.firstWhere((column) => column.name == 'Blocked');
    await container.read(boardControllerProvider).updateColumnSemantics(
          columnId: blockedColumn.columnId,
          kind: BoardColumnKind.blocked,
          isBlockedState: true,
          isEnabled: false,
        );
    await tester.pumpAndSettle();

    final taskFinder = find.text('Implement hierarchy and filtering behavior');
    await tester.tap(taskFinder);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(taskFinder);
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('item-details-status-row')), findsOneWidget);
    expect(
      find.byKey(ValueKey('item-status-chip-${blockedColumn.columnId}')),
      findsOneWidget,
    );
  });

  testWidgets(
      'add item dialog defaults to root goal and keeps advanced fields collapsed',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Item'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(find.textContaining('Creates a root'), findsNothing);
    expect(
      find.descendant(of: dialog, matching: find.textContaining('Parent:')),
      findsNothing,
    );
    expect(find.text('More options'), findsOneWidget);
    expect(find.text('Column'), findsNothing);

    await tester.tap(find.text('More options'));
    await tester.pumpAndSettle();

    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Column'), findsOneWidget);
    expect(find.text('Start date'), findsOneWidget);
    expect(find.text('Due date'), findsOneWidget);
    expect(find.text('Estimated effort (minutes)'), findsOneWidget);
  });

  testWidgets(
      'dragging an item shows near-finger column targets and dropping moves it',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    final taskCardFinder = find
        .ancestor(
          of: find.text('Implement hierarchy and filtering behavior'),
          matching: find.byType(Card),
        )
        .first;
    final gesture = await tester.startGesture(tester.getCenter(taskCardFinder));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(28, 28));
    await tester.pump();
    expect(container.read(activeDraggedItemProvider)?.itemId, 't-2');
    container.read(activeDraggedItemPositionProvider.notifier).state =
        tester.getCenter(taskCardFinder);
    await tester.pump();

    expect(find.byKey(const ValueKey('near-finger-column-overlay')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('side-column-target-c-doing')), findsNothing);
    expect(find.byKey(const ValueKey('side-column-target-c-todo')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('side-column-target-c-done')),
        findsOneWidget);

    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('side-column-target-c-todo'))),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final updatedItem = container
        .read(boardStreamProvider)
        .valueOrNull!
        .items
        .firstWhere((entry) => entry.itemId == 't-2');
    expect(updatedItem.columnId, 'c-todo');
    expect(
        find.byKey(const ValueKey('near-finger-column-overlay')), findsNothing);
  });

  testWidgets('drag overlay shows configured hidden columns as side targets',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await container.read(boardControllerProvider).createColumn('Blocked');
    final snapshot = container.read(boardStreamProvider).valueOrNull!;
    final blockedColumn =
        snapshot.columns.firstWhere((column) => column.name == 'Blocked');
    await container.read(boardControllerProvider).updateColumnSemantics(
          columnId: blockedColumn.columnId,
          kind: BoardColumnKind.blocked,
          isBlockedState: true,
          isEnabled: false,
        );
    await tester.pumpAndSettle();

    final taskCardFinder = find
        .ancestor(
          of: find.text('Implement hierarchy and filtering behavior'),
          matching: find.byType(Card),
        )
        .first;
    final gesture = await tester.startGesture(tester.getCenter(taskCardFinder));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(28, 28));
    await tester.pump();

    expect(find.byKey(const ValueKey('near-finger-column-overlay')),
        findsOneWidget);
    expect(
      find.byKey(ValueKey('side-column-target-${blockedColumn.columnId}')),
      findsOneWidget,
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'edge-docked column targets keep later columns visible on shorter screens',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 540);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    for (final name in const [
      'Review',
      'QA',
      'Blocked',
      'Ready',
      'Later',
      'Icebox',
      'Archive',
    ]) {
      await container.read(boardControllerProvider).createColumn(name);
    }
    await tester.pumpAndSettle();

    final snapshot = container.read(boardStreamProvider).valueOrNull!;
    final orderedColumns = [...snapshot.columns]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final lastColumn = orderedColumns.last;

    final taskCardFinder = find
        .ancestor(
          of: find.text('Implement hierarchy and filtering behavior'),
          matching: find.byType(Card),
        )
        .first;
    final gesture = await tester.startGesture(tester.getCenter(taskCardFinder));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(28, 28));
    await tester.pump();

    expect(find.byKey(const ValueKey('near-finger-column-overlay')),
        findsOneWidget);

    final lastTarget =
        find.byKey(ValueKey('side-column-target-${lastColumn.columnId}'));
    expect(lastTarget, findsOneWidget);

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getTopLeft(lastTarget).dy, greaterThanOrEqualTo(0));
    expect(
      tester.getBottomRight(lastTarget).dy,
      lessThanOrEqualTo(screenHeight),
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'all-boards drag overlay uses the dragged item board columns only',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await container.read(boardControllerProvider).createBoard('Ops Board');
    final secondBoardId = container.read(currentBoardIdProvider);
    await container.read(boardControllerProvider).createColumn('Review');
    final secondBoardSnapshot =
        await container.read(localBoardStoreProvider).getBoard(secondBoardId);
    final reviewColumn = secondBoardSnapshot.columns.firstWhere(
      (column) => column.name == 'Review',
    );

    container.read(boardControllerProvider).switchBoard(defaultBoardId);
    container.read(workspaceSelectedBoardIdsProvider.notifier).state = {};
    await tester.pumpAndSettle();

    final taskCardFinder = find
        .ancestor(
          of: find.text('Implement hierarchy and filtering behavior'),
          matching: find.byType(Card),
        )
        .first;
    final gesture = await tester.startGesture(tester.getCenter(taskCardFinder));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(24, 24));
    await tester.pump();
    expect(container.read(activeDraggedItemProvider)?.itemId, 't-2');
    container.read(activeDraggedItemPositionProvider.notifier).state =
        tester.getCenter(taskCardFinder);
    await tester.pump();

    expect(find.byKey(const ValueKey('near-finger-column-overlay')),
        findsOneWidget);
    expect(
      find.byKey(ValueKey('side-column-target-${reviewColumn.columnId}')),
      findsNothing,
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('all-boards kanban allows dragging items from a non-active board',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await container.read(boardControllerProvider).createBoard('Ops Board');
    final secondBoardId = container.read(currentBoardIdProvider);
    final created = await container.read(boardControllerProvider).createItem(
          title: 'Ops Task',
          type: WorkItemType.task,
          toColumnId: '$secondBoardId-c-doing',
        );

    container.read(boardControllerProvider).switchBoard(defaultBoardId);
    container.read(workspaceSelectedBoardIdsProvider.notifier).state = {};
    await tester.pumpAndSettle();

    final opsTaskCardFinder = find
        .ancestor(
          of: find.text('Ops Task'),
          matching: find.byType(Card),
        )
        .first;
    final gesture =
        await tester.startGesture(tester.getCenter(opsTaskCardFinder));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(24, 24));
    await tester.pump();

    expect(container.read(activeDraggedItemProvider)?.itemId, created.itemId);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'focused item drives context-first defaults in main add item flow',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    container.read(focusedItemIdProvider.notifier).state = 'g-1';
    await tester.pump();

    await tester.tap(find.text('Add Item'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('Parent: Goal - Ship PlanDone MVP'),
      ),
      findsOneWidget,
    );
    expect(
      container.read(focusedItemIdProvider),
      'g-1',
    );
  });

  testWidgets(
      'create item parent picker only shows higher-level parent options',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    container.read(focusedItemIdProvider.notifier).state = 'g-1';
    await tester.pump();

    await tester.tap(find.text('Add Item'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('More options'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('create-parent-g-1')));
    await tester.pumpAndSettle();

    expect(find.text('Goal: Ship PlanDone MVP'), findsWidgets);
    expect(find.text('Project: Core board + hierarchy UX'), findsNothing);
    expect(
      find.text('Task: Implement hierarchy and filtering behavior'),
      findsNothing,
    );
    expect(
      find.text('Action: Add parent-child navigation in item cards'),
      findsNothing,
    );
  });

  testWidgets('creating from a focused item keeps the original focus',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    container.read(focusedItemIdProvider.notifier).state = 'g-1';
    await tester.pump();

    await tester.tap(find.text('Add Item'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Anchored project');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    final snapshot = container.read(boardStreamProvider).valueOrNull;
    expect(snapshot, isNotNull);
    expect(
      snapshot!.items.any((item) => item.title == 'Anchored project'),
      isTrue,
    );
    expect(container.read(focusedItemIdProvider), 'g-1');
  });

  testWidgets(
      'hierarchy view ignores stale filters, keeps selection while scrolling, clears on outside taps, and overlays branch controls',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    container.read(boardVisibilityFilterProvider.notifier).state = {
      WorkItemType.action,
    };
    container.read(boardTagFilterProvider.notifier).state = 'no-match';
    container.read(boardTextQueryProvider.notifier).state = 'also-no-match';
    container.read(focusModeEnabledProvider.notifier).state = true;
    container.read(focusedItemIdProvider.notifier).state = 'a-3';
    container.read(collapsedHierarchyItemIdsProvider.notifier).state =
        <String>{};

    container
        .read(boardControllerProvider)
        .setPlanningView(BoardPlanningView.hierarchy);
    await tester.pumpAndSettle();

    expect(find.text('Ship PlanDone MVP'), findsOneWidget);
    expect(find.text('Core board + hierarchy UX'), findsOneWidget);

    container.read(focusedItemIdProvider.notifier).state = 'g-1';
    await tester.pumpAndSettle();

    expect(container.read(focusedItemIdProvider), 'g-1');
    expect(container.read(selectedHierarchyItemIdProvider), isNull);
    expect(find.byTooltip('Collapse all branches'), findsOneWidget);

    final projectTopBeforeBranchControls =
        tester.getTopLeft(find.text('Core board + hierarchy UX')).dy;

    container.read(selectedHierarchyItemIdProvider.notifier).state =
        'board-1::g-1';
    await tester.pumpAndSettle();

    expect(container.read(focusedItemIdProvider), 'g-1');
    expect(container.read(selectedHierarchyItemIdProvider), 'board-1::g-1');
    expect(find.byTooltip('Clear selected item'), findsOneWidget);
    expect(find.byTooltip('Collapse this branch'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Core board + hierarchy UX')).dy,
      projectTopBeforeBranchControls,
    );

    await tester
        .tap(find.byKey(const ValueKey('hierarchy-overlay-collapse-branch')));
    await tester.pumpAndSettle();

    expect(container.read(selectedHierarchyItemIdProvider), 'board-1::g-1');
    expect(find.text('Core board + hierarchy UX'), findsNothing);
    expect(find.byTooltip('Expand this branch'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('hierarchy-overlay-expand-branch')));
    await tester.pumpAndSettle();

    expect(find.text('Ship PlanDone MVP'), findsOneWidget);
    expect(find.text('Core board + hierarchy UX'), findsOneWidget);

    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();

    expect(container.read(focusedItemIdProvider), 'g-1');
    expect(container.read(selectedHierarchyItemIdProvider), 'board-1::g-1');

    await tester.tapAt(
      tester.getTopLeft(find.byType(Scrollable).first) + const Offset(12, 12),
    );
    await tester.pumpAndSettle();

    expect(container.read(focusedItemIdProvider), isNull);
    expect(container.read(selectedHierarchyItemIdProvider), isNull);
  });

  testWidgets(
      'hierarchy collapse state survives view switches and workspace restart',
      (WidgetTester tester) async {
    final sharedPreferences = InMemoryHierarchyViewPreferencesRepository(
      userId: _signedInSession.user.uid,
    );
    final firstContainer = _createTestContainer(
      _signedInSession,
      overrides: [
        hierarchyViewPreferencesRepositoryProvider.overrideWithValue(
          sharedPreferences,
        ),
      ],
    );

    await tester.pumpWidget(_buildAppWithContainer(firstContainer));
    await tester.pumpAndSettle();
    firstContainer
        .read(boardControllerProvider)
        .setPlanningView(BoardPlanningView.hierarchy);
    await tester.pumpAndSettle();
    firstContainer.read(selectedHierarchyItemIdProvider.notifier).state =
        'board-1::g-1';
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Collapse this branch'));
    await tester.pumpAndSettle();
    expect(find.text('Core board + hierarchy UX'), findsNothing);
    expect(
      await sharedPreferences.loadCollapsedItemIds(),
      contains('board-1::g-1'),
    );

    firstContainer
        .read(boardControllerProvider)
        .setPlanningView(BoardPlanningView.kanban);
    await tester.pumpAndSettle();
    firstContainer
        .read(boardControllerProvider)
        .setPlanningView(BoardPlanningView.hierarchy);
    await tester.pumpAndSettle();

    expect(find.text('Core board + hierarchy UX'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    firstContainer.dispose();

    final restoredContainer = _createTestContainer(
      _signedInSession,
      overrides: [
        hierarchyViewPreferencesRepositoryProvider.overrideWithValue(
          sharedPreferences,
        ),
      ],
    );
    addTearDown(restoredContainer.dispose);
    await tester.pumpWidget(_buildAppWithContainer(restoredContainer));
    await tester.pumpAndSettle();
    restoredContainer
        .read(boardControllerProvider)
        .setPlanningView(BoardPlanningView.hierarchy);
    await tester.pumpAndSettle();

    expect(
      restoredContainer.read(collapsedHierarchyItemIdsProvider),
      contains('board-1::g-1'),
    );
    expect(find.text('Core board + hierarchy UX'), findsNothing);
  });

  testWidgets('hierarchy archived filter shows only archived items',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await container.read(boardControllerProvider).updateItem(
          itemId: 'g-1',
          archived: true,
        );
    await tester.pumpAndSettle();
    expect(
      container
          .read(boardStreamProvider)
          .valueOrNull!
          .items
          .firstWhere((item) => item.itemId == 'g-1')
          .archived,
      isTrue,
    );
    container.read(boardPlanningViewProvider.notifier).state =
        BoardPlanningView.hierarchy;
    container.read(showArchivedOnlyProvider.notifier).state = true;
    await tester.pumpAndSettle();

    expect(find.text('Ship PlanDone MVP'), findsOneWidget);
    expect(find.text('Core board + hierarchy UX'), findsNothing);

    container.read(showArchivedOnlyProvider.notifier).state = false;
    await tester.pumpAndSettle();

    expect(find.text('Ship PlanDone MVP'), findsNothing);
    expect(find.text('Core board + hierarchy UX'), findsOneWidget);
  });

  testWidgets(
      'hierarchy selection and collapsed branches persist across active board changes',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await container.read(boardControllerProvider).createBoard('Ops Board');
    final secondBoardId = container.read(currentBoardIdProvider);
    await container.read(boardControllerProvider).createItem(
          title: 'Ops Goal',
          type: WorkItemType.goal,
          toColumnId: '$secondBoardId-c-doing',
        );

    container.read(workspaceSelectedBoardIdsProvider.notifier).state = {};
    container
        .read(boardControllerProvider)
        .setPlanningView(BoardPlanningView.hierarchy);
    await tester.pumpAndSettle();

    container.read(selectedHierarchyItemIdProvider.notifier).state =
        'board-1::g-1';
    container.read(collapsedHierarchyItemIdsProvider.notifier).state = {
      'board-1::g-1',
    };
    await tester.pumpAndSettle();

    container.read(boardControllerProvider).switchBoard(secondBoardId);
    await tester.pumpAndSettle();

    expect(container.read(selectedHierarchyItemIdProvider), 'board-1::g-1');
    expect(
      container.read(collapsedHierarchyItemIdsProvider),
      contains('board-1::g-1'),
    );
    expect(find.byTooltip('Collapse selected branch'), findsOneWidget);
  });

  testWidgets(
      'multi-board hierarchy tap selection does not switch active board or reopen other branches',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await container.read(boardControllerProvider).createBoard('Ops Board');
    final secondBoardId = container.read(currentBoardIdProvider);
    final localStore = container.read(localBoardStoreProvider);
    final now = DateTime(2026, 3, 21, 12);

    await localStore.upsertItem(
      WorkItem(
        itemId: 'ops-goal',
        boardId: secondBoardId,
        title: 'Ops Goal',
        type: WorkItemType.goal,
        columnId: '$secondBoardId-c-doing',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await localStore.upsertItem(
      WorkItem(
        itemId: 'ops-project',
        boardId: secondBoardId,
        parentId: 'ops-goal',
        title: 'Ops Project',
        type: WorkItemType.project,
        columnId: '$secondBoardId-c-doing',
        createdAt: now,
        updatedAt: now,
      ),
    );

    container.read(boardControllerProvider).switchBoard(defaultBoardId);
    container.read(workspaceSelectedBoardIdsProvider.notifier).state = {};
    container
        .read(boardControllerProvider)
        .setPlanningView(BoardPlanningView.hierarchy);
    await tester.pumpAndSettle();

    container.read(selectedHierarchyItemIdProvider.notifier).state =
        'board-1::g-1';
    container.read(collapsedHierarchyItemIdsProvider.notifier).state = {
      'board-1::g-1',
    };
    await tester.pumpAndSettle();

    expect(find.text('Core board + hierarchy UX'), findsNothing);
    expect(container.read(currentBoardIdProvider), defaultBoardId);

    final opsGoalTile =
        find.byKey(ValueKey('board-item-tap-$secondBoardId-ops-goal'));
    await tester.scrollUntilVisible(
      opsGoalTile,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    final opsGoalRect = tester.getRect(opsGoalTile);
    await tester.tapAt(opsGoalRect.centerLeft + const Offset(28, 0));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(container.read(currentBoardIdProvider), defaultBoardId);
    expect(
      container.read(selectedHierarchyItemIdProvider),
      '$secondBoardId::ops-goal',
    );
    expect(
      container.read(collapsedHierarchyItemIdsProvider),
      contains('board-1::g-1'),
    );
    expect(find.text('Core board + hierarchy UX'), findsNothing);
    expect(find.text('Ops Project'), findsOneWidget);
  });

  testWidgets(
      'multi-board hierarchy keeps duplicate item ids scoped to their own board',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await container.read(boardControllerProvider).createBoard('Ops Board');
    final secondBoardId = container.read(currentBoardIdProvider);
    final localStore = container.read(localBoardStoreProvider);
    final now = DateTime(2026, 3, 21, 12);

    await localStore.upsertItem(
      WorkItem(
        itemId: 'g-1',
        boardId: secondBoardId,
        title: 'Ops Goal',
        type: WorkItemType.goal,
        columnId: '$secondBoardId-c-doing',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await localStore.upsertItem(
      WorkItem(
        itemId: 'p-1',
        boardId: secondBoardId,
        parentId: 'g-1',
        title: 'Ops Project',
        type: WorkItemType.project,
        columnId: '$secondBoardId-c-doing',
        createdAt: now,
        updatedAt: now,
      ),
    );

    container.read(workspaceSelectedBoardIdsProvider.notifier).state = {};
    container
        .read(boardControllerProvider)
        .setPlanningView(BoardPlanningView.hierarchy);
    await tester.pumpAndSettle();

    container.read(selectedHierarchyItemIdProvider.notifier).state =
        'board-1::g-1';
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Collapse selected branch'));
    await tester.pumpAndSettle();

    expect(find.text('Core board + hierarchy UX'), findsNothing);
    expect(find.text('Ops Project'), findsOneWidget);
  });

  testWidgets(
      'hierarchy rows at the same depth stay aligned whether or not they have children',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    container
        .read(boardControllerProvider)
        .setPlanningView(BoardPlanningView.hierarchy);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Implement hierarchy and filtering behavior'),
      120,
      scrollable: find.byType(Scrollable).first,
    );

    final leafLeft = tester
        .getTopLeft(find.text('Create board page skeleton and state wiring'))
        .dx;
    final branchLeft = tester
        .getTopLeft(find.text('Implement hierarchy and filtering behavior'))
        .dx;

    expect((leafLeft - branchLeft).abs(), lessThan(1.0));
  });

  testWidgets('undo bar auto-dismisses and can be manually dismissed',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.8125;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    container.read(pendingBoardUndoOperationProvider.notifier).state =
        BoardUndoOperation(
      operationId: 'undo-widget-test',
      kind: BoardUndoOperationKind.archiveToggle,
      itemId: 'a-3',
      message: 'Item archived',
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(seconds: 2)),
      fromBoardId: 'board-1',
      toBoardId: 'board-1',
      fromArchived: false,
      toArchived: true,
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('pending-undo-bar')), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    final dismissButton = tester.widget<IconButton>(
      find.byKey(const ValueKey('pending-undo-dismiss-button')),
    );
    dismissButton.onPressed?.call();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pending-undo-bar')), findsNothing);

    container.read(pendingBoardUndoOperationProvider.notifier).state =
        BoardUndoOperation(
      operationId: 'undo-widget-expire',
      kind: BoardUndoOperationKind.archiveToggle,
      itemId: 'a-3',
      message: 'Item archived',
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(seconds: 1)),
      fromBoardId: 'board-1',
      toBoardId: 'board-1',
      fromArchived: false,
      toArchived: true,
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('pending-undo-bar')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pending-undo-bar')), findsNothing);
    expect(container.read(pendingBoardUndoOperationProvider), isNull);
  });

  testWidgets('auth page stays usable on short screens',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = _createTestContainer(null);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    expect(find.text('Sign in to PlanDone'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -80),
    );
    await tester.pump();

    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reminder center updates in place after snoozing a reminder',
      (WidgetTester tester) async {
    const accentColorValue = 0xFF0E9F6E;
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    final localStore = container.read(localBoardStoreProvider);
    final snapshot = await localStore.getBoard('board-1');
    final reminderItem =
        snapshot.items.firstWhere((item) => item.itemId == 'a-3').copyWith(
              clearStartAt: true,
              clearTargetEndAt: true,
              dueAt: DateTime(2026, 3, 19, 8),
              updatedAt: DateTime(2026, 3, 19, 8),
            );
    await localStore.upsertItem(reminderItem);
    await localStore.upsertBoard(
      snapshot.board.copyWith(
        updatedAt: DateTime(2026, 3, 19, 8),
        validationSettings: snapshot.board.validationSettings.copyWith(
          hierarchyColorGroupingByGoal: true,
          hierarchyGoalColorOverrides: const {
            'g-1': accentColorValue,
          },
        ),
      ),
    );

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Reminders'));
    await tester.pumpAndSettle();

    final bottomSheet = find.byType(BottomSheet);
    expect(bottomSheet, findsOneWidget);
    expect(
      find.descendant(
        of: bottomSheet,
        matching: find.text('Add parent-child navigation in item cards'),
      ),
      findsOneWidget,
    );
    final reminderAccent = tester.widget<Container>(
      find.descendant(
        of: bottomSheet,
        matching:
            find.byKey(const ValueKey('reminder-item-accent-board-1-a-3')),
      ),
    );
    final reminderAccentDecoration =
        reminderAccent.decoration! as BoxDecoration;
    expect(reminderAccentDecoration.color, const Color(accentColorValue));

    await tester.tap(
      find.descendant(
        of: bottomSheet,
        matching: find.text('Snooze'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing needs attention right now.'), findsOneWidget);
  });

  testWidgets('calendar cards reuse the configured item accent color',
      (WidgetTester tester) async {
    const accentColorValue = 0xFF0E9F6E;
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    final localStore = container.read(localBoardStoreProvider);
    final snapshot = await localStore.getBoard('board-1');
    final reminderItem =
        snapshot.items.firstWhere((item) => item.itemId == 'a-3').copyWith(
              dueAt: DateTime(2026, 3, 19, 8),
              updatedAt: DateTime(2026, 3, 19, 8),
            );
    await localStore.upsertItem(reminderItem);
    await localStore.upsertBoard(
      snapshot.board.copyWith(
        updatedAt: DateTime(2026, 3, 19, 8),
        validationSettings: snapshot.board.validationSettings.copyWith(
          hierarchyColorGroupingByGoal: true,
          hierarchyGoalColorOverrides: const {
            'g-1': accentColorValue,
          },
        ),
      ),
    );

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    container.read(boardVisibilityFilterProvider.notifier).state =
        <WorkItemType>{};
    container
        .read(boardControllerProvider)
        .setPlanningView(BoardPlanningView.calendar);
    await container
        .read(boardControllerProvider)
        .setCalendarSubview(BoardCalendarSubview.day);
    await container.read(boardControllerProvider).setCalendarVisibleDateKinds(
      {
        BoardCalendarMarkerKind.start,
        BoardCalendarMarkerKind.targetEnd,
        BoardCalendarMarkerKind.due,
      },
    );
    container
        .read(boardControllerProvider)
        .setCalendarAnchorDate(DateTime(2026, 3, 19));
    await tester.pumpAndSettle();

    expect(
        find.text('Add parent-child navigation in item cards'), findsWidgets);
    final calendarAccent = tester.widget<Container>(
      find.byKey(const ValueKey('calendar-placement-accent-board-1-a-3')),
    );
    final calendarAccentDecoration =
        calendarAccent.decoration! as BoxDecoration;
    expect(calendarAccentDecoration.color, const Color(accentColorValue));
  });

  testWidgets('dismissing the top reminder notice hides only the top surface',
      (WidgetTester tester) async {
    final container = _createTestContainer(
      _signedInSession,
      overrides: [
        boardActiveRemindersProvider.overrideWith(
          (ref) => AsyncValue.data([_testReminder()]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
        container.read(boardActiveRemindersProvider).valueOrNull, isNotEmpty);
    expect(
      container.read(workspaceTopAttentionNoticeProvider).valueOrNull,
      isNotNull,
    );

    final topCard = find.byKey(const ValueKey('workspace-attention-card'));
    expect(topCard, findsOneWidget);
    expect(
      find.descendant(
        of: topCard,
        matching: find.text('Add parent-child navigation in item cards'),
      ),
      findsOneWidget,
    );

    await tester
        .tap(find.descendant(of: topCard, matching: find.byTooltip('Dismiss')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('workspace-attention-card')), findsNothing);

    await tester.tap(find.byTooltip('Reminders'));
    await tester.pumpAndSettle();

    expect(
      find.text('Add parent-child navigation in item cards'),
      findsOneWidget,
    );
  });

  testWidgets('sync notice takes the top slot before reminder notices',
      (WidgetTester tester) async {
    final container = _createTestContainer(
      _signedInSession,
      overrides: [
        boardActiveRemindersProvider.overrideWith(
          (ref) => AsyncValue.data([_testReminder()]),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(syncUiStateProvider.notifier).state = const SyncUiState(
      lastError: 'Sync failed: network unavailable',
    );

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
        container.read(boardActiveRemindersProvider).valueOrNull, isNotEmpty);
    expect(
      container.read(workspaceTopAttentionNoticeProvider).valueOrNull,
      isNotNull,
    );

    final topCard = find.byKey(const ValueKey('workspace-attention-card'));
    expect(topCard, findsOneWidget);
    expect(
      find.descendant(of: topCard, matching: find.text('Sync failed')),
      findsOneWidget,
    );

    await tester
        .tap(find.descendant(of: topCard, matching: find.byTooltip('Dismiss')));
    await tester.pumpAndSettle();

    final reminderCard = find.byKey(const ValueKey('workspace-attention-card'));
    expect(reminderCard, findsOneWidget);
    expect(
      find.descendant(
        of: reminderCard,
        matching: find.text('Add parent-child navigation in item cards'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('workspace feedback bar auto-dismisses queued success feedback',
      (WidgetTester tester) async {
    final container = _createTestContainer(_signedInSession);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pumpAndSettle();

    container.read(boardControllerProvider).enqueueWorkspaceFeedback(
          'Saved successfully',
          severity: WorkspaceFeedbackSeverity.success,
        );
    await tester.pump();

    expect(
        find.byKey(const ValueKey('workspace-feedback-bar')), findsOneWidget);
    expect(find.text('Saved successfully'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-feedback-bar')), findsNothing);
  });

  testWidgets('launch overlay plays once on cold launch and then clears',
      (WidgetTester tester) async {
    final container = _createTestContainer(
      _signedInSession,
      overrides: [
        launchAnimationConfigProvider.overrideWithValue(
          const PlanDoneLaunchAnimationConfig(
            enabled: true,
            sequenceDuration: Duration(milliseconds: 220),
            reducedMotionDuration: Duration(milliseconds: 120),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildAppWithContainer(container));
    await tester.pump();

    expect(find.byKey(const ValueKey('launch-overlay')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 260));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('launch-overlay')), findsNothing);
    expect(find.text('Workspace'), findsWidgets);
  });
}
