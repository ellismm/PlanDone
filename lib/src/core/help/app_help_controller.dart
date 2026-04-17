import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../runtime/runtime_flags.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/board/data/local/drift/board_database.dart';
import '../../features/board/domain/models/board_calendar_preferences.dart';
import '../../features/board/domain/models/board_insights.dart';
import '../../features/board/domain/models/board_snapshot.dart';
import '../../features/board/domain/models/work_item.dart' as board_models;
import '../../features/board/domain/models/work_item_type.dart';
import '../../features/board/presentation/board_controller.dart';
import 'app_help.dart';

class AppHelpVisibleTarget {
  const AppHelpVisibleTarget({
    required this.spec,
    required this.link,
    required this.size,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
  });

  final AppHelpTargetSpec spec;
  final LayerLink link;
  final Size size;
  final BorderRadius borderRadius;

  AppHelpVisibleTarget copyWith({
    AppHelpTargetSpec? spec,
    LayerLink? link,
    Size? size,
    BorderRadius? borderRadius,
  }) {
    return AppHelpVisibleTarget(
      spec: spec ?? this.spec,
      link: link ?? this.link,
      size: size ?? this.size,
      borderRadius: borderRadius ?? this.borderRadius,
    );
  }
}

abstract class AppHelpPreferencesRepository {
  Future<AppHelpPreferences> load();
  Future<AppHelpPreferences> save(AppHelpPreferences preferences);
}

class InMemoryAppHelpPreferencesRepository
    implements AppHelpPreferencesRepository {
  InMemoryAppHelpPreferencesRepository({required String userId})
      : _userId = userId;

  final String _userId;

  static final Map<String, AppHelpPreferences> _byUser =
      <String, AppHelpPreferences>{};

  @override
  Future<AppHelpPreferences> load() async {
    return _byUser[_userId] ?? const AppHelpPreferences();
  }

  @override
  Future<AppHelpPreferences> save(AppHelpPreferences preferences) async {
    _byUser[_userId] = preferences;
    return preferences;
  }
}

class DriftAppHelpPreferencesRepository
    implements AppHelpPreferencesRepository {
  DriftAppHelpPreferencesRepository({
    required BoardDatabase database,
    required String userId,
  })  : _database = database,
        _storageKey = 'help_preferences_v1_${_sanitizeForKey(userId)}';

  final BoardDatabase _database;
  final String _storageKey;

  static String _sanitizeForKey(String raw) {
    return raw.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  Future<void> _ensureSettingsTable() {
    return _database.customStatement(
      'CREATE TABLE IF NOT EXISTS app_settings ('
      'key TEXT PRIMARY KEY NOT NULL, '
      'value TEXT NOT NULL'
      ')',
    );
  }

  @override
  Future<AppHelpPreferences> load() async {
    await _ensureSettingsTable();
    final rows = await _database.customSelect(
      'SELECT value FROM app_settings WHERE key = ?',
      variables: [drift.Variable(_storageKey)],
    ).get();
    final raw = rows.isEmpty ? null : rows.first.data['value'] as String?;
    if (raw == null || raw.trim().isEmpty) {
      return const AppHelpPreferences();
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return const AppHelpPreferences();
    }
    return AppHelpPreferences.fromMap(
      decoded.map((key, value) => MapEntry('$key', value)),
    );
  }

  @override
  Future<AppHelpPreferences> save(AppHelpPreferences preferences) async {
    await _ensureSettingsTable();
    await _database.customStatement(
      'INSERT OR REPLACE INTO app_settings(key, value) VALUES(?, ?)',
      [_storageKey, jsonEncode(preferences.toMap())],
    );
    return preferences;
  }
}

final appHelpModeEnabledProvider = StateProvider<bool>((ref) => false);

final appHelpShowFloatingButtonProvider = StateProvider<bool>((ref) {
  ref.watch(activeUserIdProvider);
  return false;
});

final appHelpCompletedToursProvider = StateProvider<Set<AppHelpTourId>>((ref) {
  ref.watch(activeUserIdProvider);
  return const <AppHelpTourId>{};
});

final activeAppHelpTourProvider = StateProvider<AppHelpTourProgress?>((ref) {
  ref.watch(activeUserIdProvider);
  return null;
});

final appHelpVisibleTargetsProvider =
    StateProvider<Map<String, AppHelpVisibleTarget>>((ref) {
  ref.watch(activeUserIdProvider);
  return const <String, AppHelpVisibleTarget>{};
});

final appHelpPreferencesRepositoryProvider =
    Provider<AppHelpPreferencesRepository>((ref) {
  final userId = ref.watch(boardScopeUserIdProvider);
  if (useInMemoryLocalStore) {
    return InMemoryAppHelpPreferencesRepository(userId: userId);
  }
  return DriftAppHelpPreferencesRepository(
    database: ref.watch(boardDatabaseProvider) as BoardDatabase,
    userId: userId,
  );
});

final appHelpPreferencesProvider = FutureProvider<AppHelpPreferences>((ref) {
  ref.watch(activeUserIdProvider);
  return ref.watch(appHelpPreferencesRepositoryProvider).load();
});

final appHelpCurrentTourDefinitionProvider =
    Provider<AppHelpTourDefinition?>((ref) {
  final activeTour = ref.watch(activeAppHelpTourProvider);
  if (activeTour == null) {
    return null;
  }
  return appHelpTours[activeTour.tourId];
});

final appHelpCurrentTourStepProvider = Provider<AppHelpTourStep?>((ref) {
  final activeTour = ref.watch(activeAppHelpTourProvider);
  final definition = ref.watch(appHelpCurrentTourDefinitionProvider);
  if (activeTour == null || definition == null) {
    return null;
  }
  if (activeTour.stepIndex < 0 ||
      activeTour.stepIndex >= definition.steps.length) {
    return null;
  }
  return definition.steps[activeTour.stepIndex];
});

final appHelpCurrentSurfaceTourProvider =
    Provider.family<AppHelpTourProgress?, AppHelpSurfaceId>((ref, surface) {
  final activeTour = ref.watch(activeAppHelpTourProvider);
  final definition = ref.watch(appHelpCurrentTourDefinitionProvider);
  if (activeTour == null ||
      definition == null ||
      definition.surface != surface) {
    return null;
  }
  return activeTour;
});

final appHelpControllerProvider = Provider<AppHelpController>((ref) {
  return AppHelpController(ref);
});

class AppHelpController {
  AppHelpController(this._ref);

  final Ref _ref;

  Future<AppHelpPreferences> updatePreferences(
    AppHelpPreferences preferences,
  ) async {
    final saved = await _ref.read(appHelpPreferencesRepositoryProvider).save(
          preferences,
        );
    _ref.invalidate(appHelpPreferencesProvider);
    return saved;
  }

  void setHelpModeEnabled(bool enabled) {
    _ref.read(appHelpModeEnabledProvider.notifier).state = enabled;
  }

  void toggleHelpMode() {
    final next = !_ref.read(appHelpModeEnabledProvider);
    _ref.read(appHelpModeEnabledProvider.notifier).state = next;
    if (next) {
      _ref.read(activeAppHelpTourProvider.notifier).state = null;
    }
  }

  Future<void> setShowFloatingHelpButton(bool show) async {
    _ref.read(appHelpShowFloatingButtonProvider.notifier).state = show;
    final current = await _ref.read(appHelpPreferencesProvider.future);
    await updatePreferences(
      current.copyWith(showFloatingHelpButton: show),
    );
  }

  Future<void> _markTourSeen(AppHelpTourId tourId) async {
    final current = await _ref.read(appHelpPreferencesProvider.future);
    final nextCompleted = <AppHelpTourId>{
      ...current.completedTours,
      tourId,
    };
    _ref.read(appHelpCompletedToursProvider.notifier).state = nextCompleted;
    await updatePreferences(current.copyWith(completedTours: nextCompleted));
  }

  Future<void> startTour(AppHelpTourId tourId) async {
    _ref.read(appHelpModeEnabledProvider.notifier).state = false;
    final progress = AppHelpTourProgress(
      tourId: tourId,
      stepIndex: 0,
    );
    _ref.read(activeAppHelpTourProvider.notifier).state = progress;
    await _applyTourStepState(progress);
  }

  Future<void> finishTour({bool markSeen = true}) async {
    final activeTour = _ref.read(activeAppHelpTourProvider);
    _ref.read(activeAppHelpTourProvider.notifier).state = null;
    if (markSeen && activeTour != null) {
      await _markTourSeen(activeTour.tourId);
    }
  }

  Future<void> advanceTour() async {
    final activeTour = _ref.read(activeAppHelpTourProvider);
    final definition =
        activeTour == null ? null : appHelpTours[activeTour.tourId];
    if (activeTour == null || definition == null) {
      return;
    }
    final nextIndex = activeTour.stepIndex + 1;
    if (nextIndex >= definition.steps.length) {
      await finishTour();
      return;
    }
    final nextProgress = activeTour.copyWith(stepIndex: nextIndex);
    _ref.read(activeAppHelpTourProvider.notifier).state = nextProgress;
    await _applyTourStepState(nextProgress);
  }

  Future<void> retreatTour() async {
    final activeTour = _ref.read(activeAppHelpTourProvider);
    if (activeTour == null || activeTour.stepIndex <= 0) {
      return;
    }
    final previousProgress =
        activeTour.copyWith(stepIndex: activeTour.stepIndex - 1);
    _ref.read(activeAppHelpTourProvider.notifier).state = previousProgress;
    await _applyTourStepState(previousProgress);
  }

  void registerVisibleTarget(AppHelpVisibleTarget target) {
    final key = target.spec.id.key;
    final current = _ref.read(appHelpVisibleTargetsProvider);
    final existing = current[key];
    if (existing != null &&
        existing.size == target.size &&
        identical(existing.link, target.link) &&
        existing.borderRadius == target.borderRadius &&
        existing.spec == target.spec) {
      return;
    }
    _ref.read(appHelpVisibleTargetsProvider.notifier).state = {
      ...current,
      key: target,
    };
  }

  void unregisterVisibleTarget(AppHelpTargetId targetId) {
    final current = _ref.read(appHelpVisibleTargetsProvider);
    if (!current.containsKey(targetId.key)) {
      return;
    }
    final next = {...current}..remove(targetId.key);
    _ref.read(appHelpVisibleTargetsProvider.notifier).state = next;
  }

  Future<void> _applyTourStepState(AppHelpTourProgress progress) async {
    switch (progress.tourId) {
      case AppHelpTourId.workspace:
        await _applyWorkspaceTourStep(progress.stepIndex);
        return;
      case AppHelpTourId.hierarchy:
        await _applyHierarchyTourStep(progress.stepIndex);
        return;
      case AppHelpTourId.insights:
        await _applyInsightsTourStep(progress.stepIndex);
        return;
      case AppHelpTourId.configuration:
        await _applyConfigurationTourStep(progress.stepIndex);
        return;
      case AppHelpTourId.flow:
        await _applyFlowTourStep(progress.stepIndex);
        return;
      case AppHelpTourId.calendar:
        await _applyCalendarTourStep(progress.stepIndex);
        return;
    }
  }

  Future<void> _applyWorkspaceTourStep(int stepIndex) async {
    final boardController = _ref.read(boardControllerProvider);
    _ref.read(boardWorkspaceSurfaceProvider.notifier).state =
        BoardWorkspaceSurface.board;
    _ref.read(focusModeEnabledProvider.notifier).state = false;
    _ref.read(focusedItemIdProvider.notifier).state = null;
    _ref.read(selectedHierarchyItemIdProvider.notifier).state = null;
    _ref.read(boardVisibilityFilterProvider.notifier).state = <WorkItemType>{};
    _ref.read(boardItemStateFilterProvider.notifier).state =
        BoardItemStateFilter.any;
    _ref.read(boardTagFilterProvider.notifier).state = '';
    _ref.read(boardTextQueryProvider.notifier).state = '';
    _ref.read(showOverdueOnlyProvider.notifier).state = false;
    _ref.read(showDueSoonOnlyProvider.notifier).state = false;
    _ref.read(showArchivedOnlyProvider.notifier).state = false;
    _ref.read(workspaceSearchExpandedProvider.notifier).state = stepIndex == 5;
    boardController.setPlanningView(BoardPlanningView.kanban);
    switch (stepIndex) {
      case 0:
      case 1:
      case 2:
      case 4:
      case 6:
        return;
      case 3:
        _ref.read(boardVisibilityFilterProvider.notifier).state =
            <WorkItemType>{WorkItemType.task, WorkItemType.action};
        _ref.read(showDueSoonOnlyProvider.notifier).state = true;
        return;
      case 5:
        return;
    }
  }

  Future<void> _applyHierarchyTourStep(int stepIndex) async {
    final boardController = _ref.read(boardControllerProvider);
    _ref.read(boardWorkspaceSurfaceProvider.notifier).state =
        BoardWorkspaceSurface.board;
    boardController.setPlanningView(BoardPlanningView.hierarchy);
    final snapshot = await _ref.read(boardStreamProvider.future);
    final focusItem = _findHierarchyTourFocusItem(snapshot);
    final focusKey =
        focusItem == null ? null : _hierarchyNodeKeyForItem(focusItem);
    void applyHierarchyState() {
      _ref.read(selectedHierarchyItemIdProvider.notifier).state = focusKey;
      switch (stepIndex) {
        case 0:
          if (focusItem != null &&
              _itemHasHierarchyChildren(snapshot, focusItem)) {
            _ref.read(collapsedHierarchyItemIdsProvider.notifier).state =
                <String>{_hierarchyNodeKeyForItem(focusItem)};
          } else {
            _ref.read(collapsedHierarchyItemIdsProvider.notifier).state =
                <String>{};
          }
          return;
        case 1:
          _ref.read(collapsedHierarchyItemIdsProvider.notifier).state =
              <String>{};
          return;
      }
    }

    applyHierarchyState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_ref.read(boardPlanningViewProvider) !=
            BoardPlanningView.hierarchy) {
          return;
        }
        applyHierarchyState();
      });
    });
  }

  Future<void> _applyInsightsTourStep(int stepIndex) async {
    switch (stepIndex) {
      case 0:
      case 1:
      case 2:
        _ref.read(selectedBoardInsightsRangeProvider.notifier).state =
            BoardInsightsRange.sevenDays;
        return;
      case 3:
      case 4:
        _ref.read(selectedBoardInsightsRangeProvider.notifier).state =
            BoardInsightsRange.thirtyDays;
        return;
    }
  }

  Future<void> _applyConfigurationTourStep(int stepIndex) async {
    switch (stepIndex) {
      case 0:
      case 1:
      case 2:
      case 3:
      case 4:
        return;
    }
  }

  Future<void> _applyFlowTourStep(int stepIndex) async {
    final boardController = _ref.read(boardControllerProvider);
    await boardController.setFlowMotionEnabled(true);

    switch (stepIndex) {
      case 0:
        await boardController.setFlowVisibleTypes(
          const <WorkItemType>{WorkItemType.action},
        );
        return;
      case 1:
      case 2:
      case 3:
        return;
    }
  }

  Future<void> _applyCalendarTourStep(int stepIndex) async {
    final boardController = _ref.read(boardControllerProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    boardController.setPlanningView(BoardPlanningView.calendar);
    boardController.setCalendarAnchorDate(today);

    switch (stepIndex) {
      case 0:
        await boardController.setCalendarSubview(BoardCalendarSubview.month);
        await boardController.setCalendarShowUnscheduled(false);
        return;
      case 1:
        await boardController.setCalendarSubview(BoardCalendarSubview.week);
        await boardController.setCalendarShowUnscheduled(false);
        return;
      case 2:
        await boardController.setCalendarSubview(BoardCalendarSubview.week);
        await boardController.setCalendarShowUnscheduled(true);
        return;
    }
  }

  String _hierarchyNodeKeyForItem(board_models.WorkItem item) {
    return '${item.boardId}::${item.itemId}';
  }

  board_models.WorkItem? _findHierarchyTourFocusItem(BoardSnapshot snapshot) {
    final items = [...snapshot.items]..sort((a, b) {
        final bySortOrder = a.sortOrder.compareTo(b.sortOrder);
        if (bySortOrder != 0) return bySortOrder;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    if (items.isEmpty) return null;

    final childCounts = <String, int>{};
    for (final item in items) {
      final parentId = item.parentId;
      if (parentId == null) continue;
      childCounts[parentId] = (childCounts[parentId] ?? 0) + 1;
    }

    for (final item in items) {
      if ((childCounts[item.itemId] ?? 0) > 0) {
        return item;
      }
    }
    return items.first;
  }

  bool _itemHasHierarchyChildren(
    BoardSnapshot snapshot,
    board_models.WorkItem item,
  ) {
    for (final candidate in snapshot.items) {
      if (candidate.parentId == item.itemId &&
          candidate.boardId == item.boardId) {
        return true;
      }
    }
    return false;
  }
}
