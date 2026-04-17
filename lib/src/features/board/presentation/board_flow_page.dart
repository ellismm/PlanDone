// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_navigation_shell.dart';
import '../../../app_routes.dart';
import '../../../core/help/app_help.dart';
import '../../../core/help/app_help_controller.dart';
import '../../../core/help/app_help_widgets.dart';
import '../domain/models/autofill_settings.dart';
import '../domain/models/board.dart';
import '../domain/models/board_flow.dart';
import '../domain/models/board_snapshot.dart';
import '../domain/models/board_validation_settings.dart';
import '../domain/models/column.dart';
import '../domain/models/work_item.dart';
import '../domain/models/work_item_type.dart';
import '../domain/policies/board_permissions.dart';
import '../domain/policies/board_validation_policy.dart';
import '../domain/policies/create_item_defaults_policy.dart';
import '../domain/policies/workflow_semantics_policy.dart';
import 'board_controller.dart';
import 'board_item_details_sheet.dart';
import 'board_view_ui.dart';
import 'workspace_attention.dart';

const _flowControlsHelpSpec = AppHelpTargetSpec(
  id: AppHelpTargetIds.flowControls,
  title: 'Flow controls',
  description:
      'These controls decide which boards and item types are part of today’s Flow sweep, and how lively the playfield feels.',
  whenToUse:
      'Use them when the playfield feels too broad, too narrow, or pointed at the wrong boards.',
  whatHappens:
      'Changing board scope, type filters, speed, or motion updates the playfield immediately.',
  icon: Icons.tune_outlined,
  tourId: AppHelpTourId.flow,
);

const _flowPlayfieldHelpSpec = AppHelpTargetSpec(
  id: AppHelpTargetIds.flowPlayfield,
  title: 'Flow playfield',
  description:
      'This is the sorting surface where today’s open actions float around waiting for a decision.',
  whenToUse:
      'Use it when you want to rapidly decide what to do next instead of manually opening each item from a list.',
  whatHappens:
      'Touch and drag a card to sort it, drag the new-item puck to create something fresh, double tap a card to open details, or swipe through empty playfield space to bat cards around like an air-hockey mallet.',
  icon: Icons.auto_awesome_motion_outlined,
  tourId: AppHelpTourId.flow,
);

const _flowTodayCountHelpSpec = AppHelpTargetSpec(
  id: AppHelpTargetIds.flowTodayCount,
  title: 'Left today',
  description: 'This count tracks how many Flow items still need a pass today.',
  whenToUse:
      'Use it when you want a quick sense of whether you are done triaging or still have a few more decisions to make.',
  whatHappens:
      'Once you act on an item in Flow, it drops out of the count until the next day unless it changes again.',
  icon: Icons.check_circle_outline,
  tourId: AppHelpTourId.flow,
);

const _flowActionRingHelpSpec = AppHelpTargetSpec(
  id: AppHelpTargetIds.flowActionRing,
  title: 'Flow decision ring',
  description:
      'The ring is where Flow turns a floating card into a real decision.',
  whenToUse:
      'Use it while dragging a card when you know whether it should be done now, scheduled, moved, completed, or deferred.',
  whatHappens:
      'Dropping on a target applies the action right away and keeps the item from coming back into Flow again today.',
  icon: Icons.control_camera_outlined,
  tourId: AppHelpTourId.flow,
);

class BoardFlowPage extends ConsumerStatefulWidget {
  const BoardFlowPage({super.key});

  @override
  ConsumerState<BoardFlowPage> createState() => _BoardFlowPageState();
}

class _BoardFlowPageState extends ConsumerState<BoardFlowPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hoverController;
  BoardFlowCandidate? _draggedCandidate;
  bool _draggingCreatePuck = false;
  int? _createPuckPointer;
  bool? _lastMotionEnabled;
  double _motionSeconds = 0;
  final Map<String, Offset> _displayedFlowPositions = {};
  final Map<String, Offset> _flowVelocities = {};
  Offset? _flowCreatePuckPosition;
  Offset? _flowCreatePuckVelocity;
  double? _lastFlowCreatePuckSampleSeconds;
  final Map<String, _FlowCardDodgeLock> _flowCardDodgeLocks = {};
  final Map<String, _FlowPairDodgeLock> _flowPairDodgeLocks = {};
  final Map<String, double> _malletHitCooldowns = {};
  double? _lastFlowPositionSampleSeconds;
  _ActiveFlowMalletState? _activeMallet;

  bool get _createPuckRingVisible =>
      _draggingCreatePuck || _createPuckPointer != null;

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )
      ..addListener(() {
        if (!mounted || _lastMotionEnabled == false) return;
        setState(() {
          _motionSeconds = DateTime.now().microsecondsSinceEpoch / 1000000.0;
        });
      })
      ..repeat(reverse: true);
    _motionSeconds = DateTime.now().microsecondsSinceEpoch / 1000000.0;
  }

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  void _syncMotion(bool enabled) {
    if (_lastMotionEnabled == enabled) return;
    _lastMotionEnabled = enabled;
    if (enabled) {
      _lastFlowPositionSampleSeconds = null;
      _lastFlowCreatePuckSampleSeconds = null;
      _displayedFlowPositions.clear();
      _flowVelocities.clear();
      _flowCreatePuckPosition = null;
      _flowCreatePuckVelocity = null;
      _flowCardDodgeLocks.clear();
      _flowPairDodgeLocks.clear();
      _malletHitCooldowns.clear();
      if (!_hoverController.isAnimating) {
        _hoverController.repeat(reverse: true);
      }
    } else {
      _hoverController.stop();
      _hoverController.value = 0.5;
      _lastFlowPositionSampleSeconds = null;
      _lastFlowCreatePuckSampleSeconds = null;
      _displayedFlowPositions.clear();
      _flowVelocities.clear();
      _flowCreatePuckPosition = null;
      _flowCreatePuckVelocity = null;
      _flowCardDodgeLocks.clear();
      _flowPairDodgeLocks.clear();
      _malletHitCooldowns.clear();
      _activeMallet = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final planningView = ref.watch(boardPlanningViewProvider);
    final boardsAsync = ref.watch(boardsProvider);
    final flowSnapshotAsync = ref.watch(boardFlowSnapshotProvider);
    final selectedBoardIds = ref.watch(workspaceSelectedBoardIdsProvider);
    final currentBoardId = ref.watch(currentBoardIdProvider);
    final visibleTypes = ref.watch(boardFlowVisibleTypesProvider);
    final motionEnabled = ref.watch(boardFlowMotionEnabledProvider);
    final motionSpeed = ref.watch(boardFlowMotionSpeedProvider);
    final pendingUndoOperation = ref.watch(pendingBoardUndoOperationProvider);
    final feedbackQueue = ref.watch(workspaceFeedbackQueueProvider);
    final currentTourStep = ref.watch(appHelpCurrentTourStepProvider);

    _syncMotion(motionEnabled);

    return AppPrimaryScaffold(
      activeRoute: AppRoutes.flow,
      title: 'Flow',
      helpSurface: AppHelpSurfaceId.flow,
      workspaceIcon: boardPlanningViewIcon(planningView),
      workspaceSelectedIcon: boardPlanningViewSelectedIcon(planningView),
      body: Stack(
        children: [
          boardsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Text('Unable to load boards: $error'),
            ),
            data: (boards) => flowSnapshotAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Text('Unable to load Flow: $error'),
              ),
              data: (snapshot) => _buildFlowBody(
                context,
                boards: boards,
                snapshot: snapshot,
                selectedBoardIds: selectedBoardIds,
                currentBoardId: currentBoardId,
                visibleTypes: visibleTypes,
                motionEnabled: motionEnabled,
                motionSpeed: motionSpeed,
                currentTourStep: currentTourStep,
              ),
            ),
          ),
          const _FlowPreferencesBridge(),
          if (feedbackQueue.isNotEmpty)
            Positioned(
              left: 12,
              right: 12,
              bottom: pendingUndoOperation != null ? 172 : 88,
              child: _FlowFeedbackBar(message: feedbackQueue.first),
            ),
          if (pendingUndoOperation != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 88,
              child: _FlowPendingUndoBar(operation: pendingUndoOperation),
            ),
        ],
      ),
    );
  }

  Widget _buildFlowBody(
    BuildContext context, {
    required List<Board> boards,
    required BoardFlowSnapshot snapshot,
    required Set<String> selectedBoardIds,
    required String currentBoardId,
    required Set<WorkItemType> visibleTypes,
    required bool motionEnabled,
    required double motionSpeed,
    required AppHelpTourStep? currentTourStep,
  }) {
    final theme = Theme.of(context);
    final multiBoardScope = snapshot.multiBoardScope;
    final scopeLabel = _boardScopeLabel(boards, selectedBoardIds);
    final showGuidedActionRing =
        currentTourStep?.targetId == AppHelpTargetIds.flowActionRing;
    final ringVisible = _draggedCandidate != null ||
        _createPuckRingVisible ||
        showGuidedActionRing;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHelpTarget(
            spec: _flowControlsHelpSpec,
            borderRadius: BorderRadius.circular(18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scopeWidth = constraints.maxWidth >= 420
                    ? 220.0
                    : math.max(148.0, constraints.maxWidth * 0.46);
                return Wrap(
                  key: const ValueKey('flow-controls-wrap'),
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: scopeWidth),
                      child: FilledButton.tonalIcon(
                        onPressed: boards.isEmpty
                            ? null
                            : () => _showBoardSelectionSheet(
                                  context,
                                  boards: boards,
                                  selectedBoardIds: selectedBoardIds,
                                  currentBoardId: currentBoardId,
                                ),
                        icon: const Icon(Icons.dashboard_customize_outlined),
                        label: Text(
                          scopeLabel,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showFlowFiltersSheet(
                        context,
                        visibleTypes: visibleTypes,
                        motionSpeed: motionSpeed,
                      ),
                      icon: const Icon(Icons.tune),
                      label: const Text('Filters'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                    FilterChip(
                      label: Text(motionEnabled ? 'Motion on' : 'Paused'),
                      avatar: Icon(
                        motionEnabled
                            ? Icons.motion_photos_on_outlined
                            : Icons.pause_circle_outline,
                        size: 18,
                      ),
                      selected: motionEnabled,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onSelected: (selected) {
                        ref
                            .read(boardControllerProvider)
                            .setFlowMotionEnabled(selected);
                      },
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: AppHelpTarget(
              spec: _flowPlayfieldHelpSpec,
              borderRadius: BorderRadius.circular(28),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.surfaceContainerLow,
                      theme.colorScheme.surface,
                      theme.colorScheme.surfaceContainerHighest,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isShort = constraints.maxHeight < 520;
                      final visibleCount = constraints.maxWidth >= 1200
                          ? 8
                          : constraints.maxWidth >= 800
                              ? 6
                              : isShort
                                  ? 3
                                  : 4;
                      final candidates = snapshot.candidates
                          .take(visibleCount)
                          .toList(growable: false);

                      final slots = _buildCandidateSlots(
                        constraints.maxWidth,
                        constraints.maxHeight,
                        candidates.length,
                      );
                      _resolveDisplayedFlowPositions(
                        itemKeys: [
                          for (final candidate in candidates) candidate.itemKey
                        ],
                        slots: slots,
                        playfieldSize: constraints.biggest,
                        timeSeconds: _motionSeconds,
                        motionEnabled: motionEnabled,
                        motionSpeed: motionSpeed,
                      );
                      final candidateItemKeys = [
                        for (final candidate in candidates) candidate.itemKey,
                      ];
                      final createPuckRect = _resolveFlowCreatePuckRect(
                        itemKeys: candidateItemKeys,
                        slots: slots,
                        positions: _displayedFlowPositions,
                        velocities: _flowVelocities,
                        playfieldSize: constraints.biggest,
                        timeSeconds: _motionSeconds,
                        motionEnabled: motionEnabled,
                        motionSpeed: motionSpeed,
                        freezePosition: _createPuckRingVisible,
                      );
                      final positions = [
                        for (final candidate in candidates)
                          _displayedFlowPositions[candidate.itemKey] ??
                              Offset.zero,
                      ];

                      return Listener(
                        key: const ValueKey('flow-playfield'),
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: (event) => _handlePlayfieldPointerDown(
                          event,
                          itemKeys: candidateItemKeys,
                          slots: slots,
                          displayedPositions: positions,
                          createPuckRect: createPuckRect,
                          playfieldSize: constraints.biggest,
                          ringVisible: ringVisible,
                        ),
                        onPointerMove: (event) => _handlePlayfieldPointerMove(
                          event,
                          itemKeys: candidateItemKeys,
                          slots: slots,
                          playfieldSize: constraints.biggest,
                          ringVisible: ringVisible,
                        ),
                        onPointerUp: _handlePlayfieldPointerEnded,
                        onPointerCancel: _handlePlayfieldPointerCancelled,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _FlowPlayfieldPainter(
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: 0.08,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 12,
                              right: 12,
                              child: IgnorePointer(
                                child: AppHelpTarget(
                                  spec: _flowTodayCountHelpSpec,
                                  borderRadius: BorderRadius.circular(999),
                                  child: _FlowTodayCountPill(
                                    remainingTodayCount:
                                        snapshot.remainingTodayCount,
                                  ),
                                ),
                              ),
                            ),
                            if (candidates.isEmpty)
                              Positioned.fill(
                                child: _FlowEmptyState(
                                  multiBoardScope: multiBoardScope,
                                  totalTodayCount: snapshot.totalTodayCount,
                                  reviewedTodayCount:
                                      snapshot.reviewedTodayCount,
                                ),
                              ),
                            Positioned.fromRect(
                              rect: createPuckRect,
                              child: _FlowCreatePuck(
                                dragging: _createPuckRingVisible,
                                onDragStarted: () {
                                  setState(() {
                                    _draggingCreatePuck = true;
                                  });
                                },
                                onDragEnded: () {
                                  if (!mounted) return;
                                  setState(() {
                                    _draggingCreatePuck = false;
                                    _createPuckPointer = null;
                                  });
                                },
                              ),
                            ),
                            for (var index = 0;
                                index < candidates.length;
                                index++)
                              _FlowFloatingCard(
                                key: ValueKey(
                                  'flow-card-${candidates[index].item.itemId}',
                                ),
                                candidate: candidates[index],
                                position: positions[index],
                                slot: slots[index],
                                accentColor: Color(
                                  snapshot.accentColorValuesByItemKey[
                                          candidates[index].itemKey] ??
                                      theme.colorScheme.primary.toARGB32(),
                                ),
                                selected: ref.watch(focusedItemIdProvider) ==
                                    candidates[index].item.itemId,
                                showBoardName: multiBoardScope,
                                dimmed: (_draggedCandidate != null &&
                                        _draggedCandidate!.itemKey !=
                                            candidates[index].itemKey) ||
                                    _createPuckRingVisible,
                                motionEnabled: motionEnabled,
                                onTap: () => _focusItem(candidates[index]),
                                onDoubleTap: () => showBoardItemDetailsSheet(
                                  context,
                                  ref,
                                  item: candidates[index].item,
                                  allItems: candidates[index].boardItems,
                                  columns: candidates[index].boardColumns,
                                  settings:
                                      candidates[index].validationSettings,
                                  onMoveToColumn: (item, toColumnId) =>
                                      _moveItemWithUndo(
                                    context,
                                    item: item,
                                    toColumnId: toColumnId,
                                  ),
                                ),
                                onDragStarted: () {
                                  setState(() {
                                    _draggedCandidate = candidates[index];
                                  });
                                },
                                onDragEnded: () {
                                  if (!mounted) return;
                                  setState(() {
                                    _draggedCandidate = null;
                                  });
                                },
                              ),
                            if (_createPuckRingVisible)
                              _FlowCreateRing(
                                playfieldSize: constraints.biggest,
                                onTask: () => _handleCreateChoice(
                                  context,
                                  _FlowCreateChoice.task,
                                ),
                                onAction: () => _handleCreateChoice(
                                  context,
                                  _FlowCreateChoice.action,
                                ),
                                onProject: () => _handleCreateChoice(
                                  context,
                                  _FlowCreateChoice.project,
                                ),
                                onGoal: () => _handleCreateChoice(
                                  context,
                                  _FlowCreateChoice.goal,
                                ),
                                onCapture: () => _handleCreateChoice(
                                  context,
                                  _FlowCreateChoice.capture,
                                ),
                              )
                            else if (_draggedCandidate != null ||
                                showGuidedActionRing)
                              AppHelpTarget(
                                spec: _flowActionRingHelpSpec,
                                borderRadius: BorderRadius.circular(999),
                                child: _FlowActionRing(
                                  playfieldSize: constraints.biggest,
                                  onDoNow: _draggedCandidate == null
                                      ? () {}
                                      : () => _handleDoNow(
                                            context,
                                            _draggedCandidate!,
                                          ),
                                  onSchedule: _draggedCandidate == null
                                      ? () {}
                                      : () => _handleSchedule(
                                            context,
                                            _draggedCandidate!,
                                          ),
                                  onMoveColumn: _draggedCandidate == null
                                      ? () {}
                                      : () => _handleMoveColumn(
                                            context,
                                            _draggedCandidate!,
                                          ),
                                  onDone: _draggedCandidate == null
                                      ? () {}
                                      : () => _handleDone(
                                            context,
                                            _draggedCandidate!,
                                          ),
                                  onNotNow: _draggedCandidate == null
                                      ? () {}
                                      : () => _handleNotNow(
                                            context,
                                            _draggedCandidate!,
                                          ),
                                ),
                              ),
                            if (_activeMallet != null &&
                                _draggedCandidate == null &&
                                !_createPuckRingVisible &&
                                !showGuidedActionRing)
                              _FlowMalletOverlay(
                                position: _activeMallet!.position,
                                playfieldSize: constraints.biggest,
                                intensity: _activeMallet!.velocity.distance,
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handlePlayfieldPointerDown(
    PointerDownEvent event, {
    required List<String> itemKeys,
    required List<_FlowSlot> slots,
    required List<Offset> displayedPositions,
    required Rect createPuckRect,
    required Size playfieldSize,
    required bool ringVisible,
  }) {
    if (ringVisible || _draggedCandidate != null) {
      return;
    }
    if (_activeMallet != null) {
      return;
    }
    final localPosition =
        _clampPointToPlayfield(event.localPosition, playfieldSize);
    if (_flowPointHitsAnyCard(
      point: localPosition,
      itemKeys: itemKeys,
      slots: slots,
      displayedPositions: displayedPositions,
    )) {
      return;
    }
    if (createPuckRect.contains(localPosition)) {
      setState(() {
        _createPuckPointer = event.pointer;
      });
      return;
    }

    final eventSeconds = event.timeStamp.inMicroseconds / 1000000.0;
    setState(() {
      _activeMallet = _ActiveFlowMalletState(
        pointer: event.pointer,
        position: localPosition,
        velocity: Offset.zero,
        lastEventSeconds: eventSeconds,
      );
    });
  }

  void _handlePlayfieldPointerMove(
    PointerMoveEvent event, {
    required List<String> itemKeys,
    required List<_FlowSlot> slots,
    required Size playfieldSize,
    required bool ringVisible,
  }) {
    final activeMallet = _activeMallet;
    if (ringVisible ||
        _draggedCandidate != null ||
        activeMallet == null ||
        activeMallet.pointer != event.pointer) {
      return;
    }

    final eventSeconds = event.timeStamp.inMicroseconds / 1000000.0;
    final nextPosition =
        _clampPointToPlayfield(event.localPosition, playfieldSize);
    final rawDelta = nextPosition - activeMallet.position;
    final deltaSeconds = math.max(
      1 / 240,
      eventSeconds - activeMallet.lastEventSeconds,
    );
    final nextVelocity = rawDelta / deltaSeconds;

    if (rawDelta.distance < 0.5) {
      setState(() {
        _activeMallet = activeMallet.copyWith(
          position: nextPosition,
          velocity: nextVelocity,
          lastEventSeconds: eventSeconds,
        );
      });
      return;
    }

    setState(() {
      _applyFlowMalletImpulse(
        itemKeys: itemKeys,
        slots: slots,
        previousMalletPosition: activeMallet.position,
        malletPosition: nextPosition,
        malletVelocity: nextVelocity,
        playfieldSize: playfieldSize,
        positions: _displayedFlowPositions,
        velocities: _flowVelocities,
        hitCooldowns: _malletHitCooldowns,
        timeSeconds: eventSeconds,
      );
      _activeMallet = activeMallet.copyWith(
        position: nextPosition,
        velocity: nextVelocity,
        lastEventSeconds: eventSeconds,
      );
    });
  }

  void _handlePlayfieldPointerEnded(PointerUpEvent event) {
    if (_createPuckPointer == event.pointer) {
      setState(() {
        _createPuckPointer = null;
      });
    }
    final activeMallet = _activeMallet;
    if (activeMallet == null || activeMallet.pointer != event.pointer) {
      return;
    }
    setState(() {
      _activeMallet = null;
    });
  }

  void _handlePlayfieldPointerCancelled(PointerCancelEvent event) {
    if (_createPuckPointer == event.pointer) {
      setState(() {
        _createPuckPointer = null;
      });
    }
    final activeMallet = _activeMallet;
    if (activeMallet == null || activeMallet.pointer != event.pointer) {
      return;
    }
    setState(() {
      _activeMallet = null;
    });
  }

  String _boardScopeLabel(List<Board> boards, Set<String> selectedBoardIds) {
    if (boards.isEmpty) return 'No boards';
    if (selectedBoardIds.isEmpty || selectedBoardIds.length >= boards.length) {
      return 'All boards';
    }
    if (selectedBoardIds.length == 1) {
      final boardId = selectedBoardIds.first;
      final board = boards
          .where((entry) => entry.boardId == boardId)
          .cast<Board?>()
          .firstWhere((_) => true, orElse: () => null);
      return board?.name ?? '1 board';
    }
    return '${selectedBoardIds.length} boards';
  }

  List<Offset> _resolveDisplayedFlowPositions({
    required List<String> itemKeys,
    required List<_FlowSlot> slots,
    required Size playfieldSize,
    required double timeSeconds,
    required bool motionEnabled,
    required double motionSpeed,
  }) {
    final currentKeys = itemKeys.toSet();
    _displayedFlowPositions.removeWhere(
      (itemKey, _) => !currentKeys.contains(itemKey),
    );
    _flowVelocities.removeWhere((itemKey, _) => !currentKeys.contains(itemKey));
    _flowCardDodgeLocks.removeWhere(
      (itemKey, _) => !currentKeys.contains(itemKey),
    );
    _flowPairDodgeLocks.removeWhere((pairKey, _) {
      final parts = pairKey.split('||');
      return parts.length != 2 ||
          !currentKeys.contains(parts[0]) ||
          !currentKeys.contains(parts[1]);
    });

    for (var index = 0; index < itemKeys.length; index++) {
      final itemKey = itemKeys[index];
      if (_displayedFlowPositions.containsKey(itemKey) &&
          _flowVelocities.containsKey(itemKey)) {
        continue;
      }
      final initialState = _baseFlowMotionState(
        playfieldSize: playfieldSize,
        slot: slots[index],
        visualIndex: index,
        itemKey: itemKey,
        timeSeconds: timeSeconds,
      );
      _displayedFlowPositions[itemKey] = initialState.position;
      _flowVelocities[itemKey] = initialState.velocity;
    }

    if (!motionEnabled) {
      _flowCardDodgeLocks.clear();
      _flowPairDodgeLocks.clear();
      return [
        for (var index = 0; index < itemKeys.length; index++)
          _displayedFlowPositions[itemKeys[index]] ?? Offset.zero,
      ];
    }

    final previousSampleSeconds = _lastFlowPositionSampleSeconds;
    _lastFlowPositionSampleSeconds = timeSeconds;
    final deltaSeconds = previousSampleSeconds == null
        ? 1 / 60
        : (timeSeconds - previousSampleSeconds).clamp(1 / 120, 0.05);
    final adjustedDeltaSeconds = deltaSeconds * motionSpeed;
    final substepCount =
        math.max(1, math.min(4, (adjustedDeltaSeconds / (1 / 60)).ceil()));
    final stepSeconds = adjustedDeltaSeconds / substepCount;

    for (var step = 0; step < substepCount; step++) {
      _advanceFlowSimulationStep(
        itemKeys: itemKeys,
        slots: slots,
        playfieldSize: playfieldSize,
        positions: _displayedFlowPositions,
        velocities: _flowVelocities,
        cardDodgeLocks: _flowCardDodgeLocks,
        pairDodgeLocks: _flowPairDodgeLocks,
        stepSeconds: stepSeconds,
      );
    }

    return [
      for (var index = 0; index < itemKeys.length; index++)
        _displayedFlowPositions[itemKeys[index]] ?? Offset.zero,
    ];
  }

  Rect _resolveFlowCreatePuckRect({
    required List<String> itemKeys,
    required List<_FlowSlot> slots,
    required Map<String, Offset> positions,
    required Map<String, Offset> velocities,
    required Size playfieldSize,
    required double timeSeconds,
    required bool motionEnabled,
    required double motionSpeed,
    required bool freezePosition,
  }) {
    const itemKey = _flowCreatePuckItemKey;
    const visualIndex = 97;
    final slot = _flowCreatePuckSlot();

    _flowCreatePuckPosition ??= _flowCreatePuckInitialPosition(playfieldSize);
    _flowCreatePuckVelocity ??=
        _seededFlowVelocity(visualIndex: visualIndex, itemKey: itemKey);

    if (!motionEnabled || freezePosition) {
      return _flowRectForPosition(_flowCreatePuckPosition!, slot);
    }

    final previousSampleSeconds = _lastFlowCreatePuckSampleSeconds;
    _lastFlowCreatePuckSampleSeconds = timeSeconds;
    final deltaSeconds = previousSampleSeconds == null
        ? 1 / 60
        : (timeSeconds - previousSampleSeconds).clamp(1 / 120, 0.05);
    final adjustedDeltaSeconds = deltaSeconds * motionSpeed;
    final substepCount =
        math.max(1, math.min(4, (adjustedDeltaSeconds / (1 / 60)).ceil()));
    final stepSeconds = adjustedDeltaSeconds / substepCount;

    for (var step = 0; step < substepCount; step++) {
      final currentVelocity = _flowCreatePuckVelocity ?? Offset.zero;
      final baseVelocity =
          _seededFlowVelocity(visualIndex: visualIndex, itemKey: itemKey);
      final targetSpeed = baseVelocity.distance;
      final currentSpeed = currentVelocity.distance;
      final direction = currentSpeed < 0.001
          ? _normalizeOffset(baseVelocity)
          : currentVelocity / currentSpeed;
      final nextSpeed = currentSpeed < 0.001
          ? targetSpeed
          : currentSpeed + (targetSpeed - currentSpeed) * 0.03;
      _flowCreatePuckVelocity = direction * nextSpeed;

      final moved = _moveFlowCardWithinBounds(
        position: _flowCreatePuckPosition ?? Offset.zero,
        velocity: _flowCreatePuckVelocity ?? Offset.zero,
        slot: slot,
        playfieldSize: playfieldSize,
        stepSeconds: stepSeconds,
      );
      _flowCreatePuckPosition = moved.position;
      _flowCreatePuckVelocity = moved.velocity;
    }

    return _flowRectForPosition(_flowCreatePuckPosition!, slot);
  }

  Future<void> _showFlowFiltersSheet(
    BuildContext context, {
    required Set<WorkItemType> visibleTypes,
    required double motionSpeed,
  }) async {
    var workingTypes = {...visibleTypes};
    var workingMotionSpeed = motionSpeed;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          void updateTypes(WorkItemType type, bool selected) {
            final next = {...workingTypes};
            if (selected) {
              next.add(type);
            } else if (next.length > 1) {
              next.remove(type);
            }
            setModalState(() {
              workingTypes = next;
            });
            ref.read(boardControllerProvider).setFlowVisibleTypes(next);
          }

          String speedLabel(double speed) {
            if ((speed - boardFlowDefaultMotionSpeed).abs() < 0.01) {
              return 'Normal';
            }
            return '${speed.toStringAsFixed(1)}x';
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Flow filters',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'These changes apply immediately so the playfield updates right away.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Types',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilterChip(
                          label: const Text('Task'),
                          selected: workingTypes.contains(WorkItemType.task),
                          onSelected: (selected) =>
                              updateTypes(WorkItemType.task, selected),
                        ),
                        FilterChip(
                          label: const Text('Action'),
                          selected: workingTypes.contains(WorkItemType.action),
                          onSelected: (selected) =>
                              updateTypes(WorkItemType.action, selected),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Speed',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Normal is the current motion. Slow it down or make it livelier.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Slow',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Expanded(
                          child: Slider(
                            key: const ValueKey('flow-speed-slider'),
                            value: workingMotionSpeed,
                            min: boardFlowMinMotionSpeed,
                            max: boardFlowMaxMotionSpeed,
                            divisions: 6,
                            label: speedLabel(workingMotionSpeed),
                            onChanged: (next) {
                              setModalState(() {
                                workingMotionSpeed = next;
                              });
                              ref
                                  .read(boardControllerProvider)
                                  .setFlowMotionSpeed(next);
                            },
                          ),
                        ),
                        Text(
                          'Fast',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        speedLabel(workingMotionSpeed),
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
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

  Future<void> _showBoardSelectionSheet(
    BuildContext context, {
    required List<Board> boards,
    required Set<String> selectedBoardIds,
    required String currentBoardId,
  }) async {
    if (boards.isEmpty) return;

    final allBoardIds = {for (final board in boards) board.boardId};
    var working = selectedBoardIds.isEmpty
        ? {...allBoardIds}
        : {...selectedBoardIds.where(allBoardIds.contains)};
    if (working.isEmpty) {
      working = {...allBoardIds};
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final allSelected = working.length == allBoardIds.length;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Board scope',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('All boards'),
                    value: allSelected,
                    onChanged: (value) {
                      setModalState(() {
                        if (value == true) {
                          working = {...allBoardIds};
                        } else {
                          working = {currentBoardId};
                        }
                      });
                    },
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final board in boards)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            onTap: () {
                              setModalState(() {
                                if (working.contains(board.boardId)) {
                                  if (working.length > 1) {
                                    working.remove(board.boardId);
                                  }
                                } else {
                                  working.add(board.boardId);
                                }
                              });
                            },
                            leading: Checkbox(
                              value: working.contains(board.boardId),
                              onChanged: (value) {
                                setModalState(() {
                                  if (value == true) {
                                    working.add(board.boardId);
                                  } else if (working.length > 1) {
                                    working.remove(board.boardId);
                                  }
                                });
                              },
                            ),
                            title: Text(board.name),
                            trailing: board.boardId == currentBoardId
                                ? const Chip(label: Text('Active'))
                                : null,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () {
                        final normalized = working.length >= allBoardIds.length
                            ? <String>{}
                            : working;
                        ref
                            .read(workspaceSelectedBoardIdsProvider.notifier)
                            .state = normalized;

                        final allowedIds =
                            normalized.isEmpty ? allBoardIds : normalized;
                        if (!allowedIds
                            .contains(ref.read(currentBoardIdProvider))) {
                          final fallback = boards
                              .where(
                                  (entry) => allowedIds.contains(entry.boardId))
                              .map((entry) => entry.boardId)
                              .cast<String?>()
                              .firstWhere((_) => true, orElse: () => null);
                          if (fallback != null) {
                            ref
                                .read(boardControllerProvider)
                                .switchBoard(fallback);
                          }
                        }
                        Navigator.of(context).pop();
                      },
                      child: const Text('Apply'),
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

  void _focusItem(BoardFlowCandidate candidate) {
    if (ref.read(currentBoardIdProvider) != candidate.item.boardId) {
      ref.read(boardControllerProvider).switchBoard(candidate.item.boardId);
    }
    ref.read(focusedItemIdProvider.notifier).state = candidate.item.itemId;
    ref.read(selectedHierarchyItemIdProvider.notifier).state = null;
    ref.read(focusModeEnabledProvider.notifier).state = false;
  }

  Future<bool> _runGuardedAction(
    BuildContext context,
    Future<Object?> Function() action,
  ) async {
    try {
      await action();
      return true;
    } on Exception catch (error) {
      if (!mounted) return false;
      ref.read(boardControllerProvider).enqueueWorkspaceFeedback(
            'Action failed: $error',
            severity: WorkspaceFeedbackSeverity.error,
          );
      return false;
    }
  }

  Future<bool> _moveItemWithUndo(
    BuildContext context, {
    required WorkItem item,
    required String toColumnId,
  }) async {
    if (item.columnId == toColumnId) return false;
    final moved = await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).moveItem(
            boardId: item.boardId,
            itemId: item.itemId,
            toColumnId: toColumnId,
          ),
    );
    if (!moved) return false;
    ref.read(boardControllerProvider).stageMoveUndo(
          item: item,
          fromBoardId: item.boardId,
          fromColumnId: item.columnId,
          toBoardId: item.boardId,
          toColumnId: toColumnId,
        );
    return true;
  }

  Future<bool> _rescheduleItemDueDateWithUndo(
    BuildContext context, {
    required WorkItem item,
    required DateTime dueAt,
  }) async {
    final normalizedDueAt = DateTime(dueAt.year, dueAt.month, dueAt.day);
    final previousDueAt = item.dueAt == null
        ? null
        : DateTime(item.dueAt!.year, item.dueAt!.month, item.dueAt!.day);
    if (previousDueAt != null &&
        previousDueAt.year == normalizedDueAt.year &&
        previousDueAt.month == normalizedDueAt.month &&
        previousDueAt.day == normalizedDueAt.day) {
      return false;
    }
    final updated = await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).updateItem(
            boardId: item.boardId,
            itemId: item.itemId,
            dueAt: normalizedDueAt,
          ),
    );
    if (!updated) return false;
    ref.read(boardControllerProvider).stageDueDateUndo(
          item: item,
          fromDueAt: previousDueAt,
          toDueAt: normalizedDueAt,
        );
    return true;
  }

  Future<void> _markReviewed(BoardFlowCandidate candidate) async {
    await ref.read(boardControllerProvider).markFlowItemReviewedToday(
          item: candidate.item,
          stateToken: candidate.stateToken,
        );
  }

  BoardColumn? _doNowColumnFor(List<BoardColumn> columns) {
    final ordered = WorkflowSemanticsPolicy.normalizeColumns(columns)
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    BoardColumn? firstMatching(bool Function(BoardColumn column) predicate) {
      return ordered
          .where(predicate)
          .cast<BoardColumn?>()
          .firstWhere((_) => true, orElse: () => null);
    }

    return firstMatching(
          (column) =>
              column.isEnabled && column.kind == BoardColumnKind.inProgress,
        ) ??
        firstMatching(
          (column) =>
              column.isEnabled &&
              !column.isDoneState &&
              !column.isCancelledState &&
              column.kind != BoardColumnKind.planning &&
              column.kind != BoardColumnKind.backlog,
        ) ??
        firstMatching(
          (column) =>
              column.isEnabled &&
              !column.isDoneState &&
              !column.isCancelledState,
        ) ??
        firstMatching((column) => column.isEnabled);
  }

  Future<void> _handleDoNow(
    BuildContext context,
    BoardFlowCandidate candidate,
  ) async {
    _clearDragState();
    final targetColumn = _doNowColumnFor(candidate.boardColumns);
    if (targetColumn == null) return;
    _focusItem(candidate);
    if (targetColumn.columnId == candidate.item.columnId) {
      ref.read(boardControllerProvider).enqueueWorkspaceFeedback(
            'Already in a working column.',
            severity: WorkspaceFeedbackSeverity.info,
          );
      await _markReviewed(candidate);
      return;
    }
    final moved = await _moveItemWithUndo(
      context,
      item: candidate.item,
      toColumnId: targetColumn.columnId,
    );
    if (moved) {
      await _markReviewed(candidate);
    }
  }

  Future<void> _handleSchedule(
    BuildContext context,
    BoardFlowCandidate candidate,
  ) async {
    _clearDragState();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: candidate.item.dueAt ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    final updated = await _rescheduleItemDueDateWithUndo(
      context,
      item: candidate.item,
      dueAt: picked,
    );
    if (updated) {
      await _markReviewed(candidate);
    }
  }

  Future<void> _handleMoveColumn(
    BuildContext context,
    BoardFlowCandidate candidate,
  ) async {
    _clearDragState();
    final columns = [...candidate.boardColumns]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final selected = await showModalBottomSheet<String>(
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
                'Move column',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final column in columns)
                      ListTile(
                        key: ValueKey('flow-column-option-${column.columnId}'),
                        enabled: column.columnId != candidate.item.columnId,
                        title: Text(column.name),
                        trailing: column.columnId == candidate.item.columnId
                            ? const Chip(label: Text('Current'))
                            : null,
                        onTap: column.columnId == candidate.item.columnId
                            ? null
                            : () => Navigator.of(context).pop(column.columnId),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    final moved = await _moveItemWithUndo(
      context,
      item: candidate.item,
      toColumnId: selected,
    );
    if (moved) {
      await _markReviewed(candidate);
    }
  }

  Future<void> _handleDone(
    BuildContext context,
    BoardFlowCandidate candidate,
  ) async {
    _clearDragState();
    final completed = await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).completeReminderAsDone(
            boardId: candidate.item.boardId,
            itemId: candidate.item.itemId,
          ),
    );
    if (completed) {
      await _markReviewed(candidate);
    }
  }

  Future<void> _handleNotNow(
    BuildContext context,
    BoardFlowCandidate candidate,
  ) async {
    _clearDragState();
    await ref
        .read(boardControllerProvider)
        .suppressFlowItemUntilTomorrowMorning(
          item: candidate.item,
          stateToken: candidate.stateToken,
        );
    await _markReviewed(candidate);
    ref.read(boardControllerProvider).enqueueWorkspaceFeedback(
          'Dismissed from Flow for today.',
          severity: WorkspaceFeedbackSeverity.info,
        );
  }

  void _clearDragState() {
    if (!mounted) return;
    setState(() {
      _draggedCandidate = null;
      _draggingCreatePuck = false;
      _createPuckPointer = null;
    });
  }

  Future<void> _handleCreateChoice(
    BuildContext context,
    _FlowCreateChoice choice,
  ) async {
    _clearDragState();
    switch (choice) {
      case _FlowCreateChoice.capture:
        await _showFlowQuickCaptureDialog(context);
        return;
      case _FlowCreateChoice.goal:
        await _showFlowCreateItemDialog(
          context,
          type: WorkItemType.goal,
        );
        return;
      case _FlowCreateChoice.project:
        await _showFlowCreateItemDialog(
          context,
          type: WorkItemType.project,
        );
        return;
      case _FlowCreateChoice.task:
        await _showFlowCreateItemDialog(
          context,
          type: WorkItemType.task,
        );
        return;
      case _FlowCreateChoice.action:
        await _showFlowCreateItemDialog(
          context,
          type: WorkItemType.action,
        );
        return;
    }
  }

  Future<BoardSnapshot?> _resolveCurrentBoardSnapshot() async {
    final boardId = ref.read(currentBoardIdProvider);
    return (ref.read(boardStreamProvider).valueOrNull?.board.boardId == boardId
            ? ref.read(boardStreamProvider).valueOrNull
            : ref.read(boardSnapshotProvider(boardId)).valueOrNull) ??
        await ref.read(boardSnapshotProvider(boardId).future);
  }

  Future<void> _showFlowQuickCaptureDialog(BuildContext context) async {
    final snapshot = await _resolveCurrentBoardSnapshot();
    if (snapshot == null) return;
    final userId = ref.read(boardScopeUserIdProvider);
    final permissionProfile =
        BoardPermissions.profileFor(snapshot: snapshot, userId: userId);
    if (!permissionProfile.has(BoardCapability.modifyItems)) {
      ref.read(boardControllerProvider).enqueueWorkspaceFeedback(
            'Current role cannot create items in this board.',
            severity: WorkspaceFeedbackSeverity.error,
          );
      return;
    }

    var title = '';
    var tagsText = '';
    final submitted = await showDialog<(String, List<String>)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quick capture'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'What do you need to remember?',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => title = value,
              onSubmitted: (value) {
                final normalized = value.trim();
                if (normalized.isEmpty) return;
                Navigator.of(context).pop((normalized, const <String>[]));
              },
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: const InputDecoration(
                hintText: 'tags (optional, comma separated)',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => tagsText = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final normalized = title.trim();
              if (normalized.isEmpty) return;
              final tags = tagsText
                  .split(',')
                  .map((entry) => entry.trim())
                  .where((entry) => entry.isNotEmpty)
                  .toList();
              Navigator.of(context).pop((normalized, tags));
            },
            child: const Text('Capture'),
          ),
        ],
      ),
    );

    if (submitted == null) return;
    final ok = await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).createInboxCapture(
            title: submitted.$1,
            tags: submitted.$2,
          ),
    );
    if (!ok) return;
    ref.read(boardControllerProvider).enqueueWorkspaceFeedback(
          'Captured to inbox.',
          severity: WorkspaceFeedbackSeverity.success,
        );
  }

  Future<void> _showFlowCreateItemDialog(
    BuildContext context, {
    required WorkItemType type,
  }) async {
    final snapshot = await _resolveCurrentBoardSnapshot();
    if (snapshot == null) return;
    final userId = ref.read(boardScopeUserIdProvider);
    final permissionProfile =
        BoardPermissions.profileFor(snapshot: snapshot, userId: userId);
    if (!permissionProfile.has(BoardCapability.modifyItems)) {
      ref.read(boardControllerProvider).enqueueWorkspaceFeedback(
            'Current role cannot create items in this board.',
            severity: WorkspaceFeedbackSeverity.error,
          );
      return;
    }

    final columns = [...snapshot.columns]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    if (columns.isEmpty) return;
    final autofillSettings = ref.read(autofillSettingsProvider).valueOrNull ??
        const AutofillSettings();
    final defaults = CreateItemDefaultsPolicy.resolve(
      snapshot: snapshot,
      settings: autofillSettings,
      selectedType: type,
    );
    final parentCandidates = _flowParentCandidatesForType(
      childType: type,
      allItems: snapshot.items,
    );
    final requiresParent = _flowRequiresParentForType(
      settings: snapshot.board.validationSettings,
      type: type,
    );
    String? selectedParentId = defaults.parentId != null &&
            parentCandidates.any((item) => item.itemId == defaults.parentId)
        ? defaults.parentId
        : null;
    if (selectedParentId == null &&
        requiresParent &&
        parentCandidates.length == 1) {
      selectedParentId = parentCandidates.single.itemId;
    }
    DateTime? selectedStartAt =
        _flowDefaultCreateStartAt(columns, defaults.columnId);
    DateTime? selectedTargetEndAt;
    DateTime? selectedDueAt;
    final estimateController = TextEditingController(
      text: defaults.estimatedEffortMinutes?.toString() ?? '',
    );
    final titleController = TextEditingController();

    Future<void> pickDate({
      required BuildContext context,
      required DateTime? currentValue,
      required ValueChanged<DateTime?> onChanged,
    }) async {
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: currentValue ?? now,
        firstDate: DateTime(now.year - 10),
        lastDate: DateTime(now.year + 20),
      );
      if (picked != null) {
        onChanged(picked);
      }
    }

    final submitted = await showDialog<
        ({
          String title,
          String? parentId,
          DateTime? startAt,
          DateTime? targetEndAt,
          DateTime? dueAt,
          int? estimatedEffortMinutes,
        })>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final canSubmit = titleController.text.trim().isNotEmpty &&
              (!requiresParent || selectedParentId != null);
          return AlertDialog(
            title: Text('Add ${_flowWorkItemTypeLabel(type)}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: '${_flowWorkItemTypeLabel(type)} title',
                      border: const OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (!canSubmit) return;
                      Navigator.of(context).pop((
                        title: titleController.text.trim(),
                        parentId: selectedParentId,
                        startAt: selectedStartAt,
                        targetEndAt: selectedTargetEndAt,
                        dueAt: selectedDueAt,
                        estimatedEffortMinutes:
                            int.tryParse(estimateController.text.trim()),
                      ));
                    },
                  ),
                  if (requiresParent || parentCandidates.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: selectedParentId,
                      key: ValueKey('flow-create-parent-${type.name}'),
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText:
                            requiresParent ? 'Parent' : 'Parent (optional)',
                      ),
                      items: [
                        if (!requiresParent)
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('None'),
                          ),
                        for (final item in parentCandidates)
                          DropdownMenuItem<String?>(
                            value: item.itemId,
                            child: Text(
                              '${_flowWorkItemTypeLabel(item.type)}: ${item.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          selectedParentId = value;
                        });
                      },
                    ),
                  ],
                  if (snapshot.board.validationSettings.requireStartDate) ...[
                    const SizedBox(height: 12),
                    _FlowRequiredDateField(
                      label: 'Start date',
                      value: selectedStartAt,
                      onPick: () => pickDate(
                        context: context,
                        currentValue: selectedStartAt,
                        onChanged: (value) {
                          setState(() {
                            selectedStartAt = value;
                          });
                        },
                      ),
                    ),
                  ],
                  if (snapshot
                      .board.validationSettings.requireTargetEndDate) ...[
                    const SizedBox(height: 12),
                    _FlowRequiredDateField(
                      label: 'Target end date',
                      value: selectedTargetEndAt,
                      onPick: () => pickDate(
                        context: context,
                        currentValue: selectedTargetEndAt,
                        onChanged: (value) {
                          setState(() {
                            selectedTargetEndAt = value;
                          });
                        },
                      ),
                    ),
                  ],
                  if (snapshot.board.validationSettings.requireDueDate) ...[
                    const SizedBox(height: 12),
                    _FlowRequiredDateField(
                      label: 'Due date',
                      value: selectedDueAt,
                      onPick: () => pickDate(
                        context: context,
                        currentValue: selectedDueAt,
                        onChanged: (value) {
                          setState(() {
                            selectedDueAt = value;
                          });
                        },
                      ),
                    ),
                  ],
                  if (snapshot
                      .board.validationSettings.requireEstimatedEffort) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: estimateController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Estimated effort (minutes)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'Creates on ${snapshot.board.name} in ${columns.firstWhere((column) => column.columnId == defaults.columnId, orElse: () => columns.first).name}.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                onPressed: canSubmit
                    ? () {
                        Navigator.of(context).pop((
                          title: titleController.text.trim(),
                          parentId: selectedParentId,
                          startAt: selectedStartAt,
                          targetEndAt: selectedTargetEndAt,
                          dueAt: selectedDueAt,
                          estimatedEffortMinutes:
                              int.tryParse(estimateController.text.trim()),
                        ));
                      }
                    : null,
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );

    if (submitted == null) return;
    final created = await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).createItem(
            boardId: snapshot.board.boardId,
            title: submitted.title,
            type: type,
            toColumnId: defaults.columnId,
            parentId: submitted.parentId,
            startAt: submitted.startAt,
            targetEndAt: submitted.targetEndAt,
            dueAt: submitted.dueAt,
            tags: defaults.tags,
            estimatedEffortMinutes: submitted.estimatedEffortMinutes ??
                defaults.estimatedEffortMinutes,
          ),
    );
    if (!created) return;
    ref.read(boardControllerProvider).enqueueWorkspaceFeedback(
          '${_flowWorkItemTypeLabel(type)} added.',
          severity: WorkspaceFeedbackSeverity.success,
        );
  }
}

enum _FlowCreateChoice {
  task,
  action,
  project,
  goal,
  capture,
}

List<WorkItem> _flowParentCandidatesForType({
  required WorkItemType childType,
  required List<WorkItem> allItems,
}) {
  return BoardValidationPolicy.allowedParentCandidates(
    childType: childType,
    allItems: allItems,
  );
}

bool _flowRequiresParentForType({
  required BoardValidationSettings settings,
  required WorkItemType type,
}) {
  return switch (type) {
    WorkItemType.goal => false,
    WorkItemType.project => settings.requireParentForProjects,
    WorkItemType.task => settings.requireParentForTasks,
    WorkItemType.action => settings.requireParentForActions,
  };
}

bool _flowIsInProgressColumnForCreate(
  List<BoardColumn> columns,
  String columnId,
) {
  final column = columns
      .where((entry) => entry.columnId == columnId)
      .cast<BoardColumn?>()
      .firstWhere((_) => true, orElse: () => null);
  if (column == null) return false;
  final normalized = WorkflowSemanticsPolicy.withLegacyInference(column);
  return normalized.kind == BoardColumnKind.inProgress;
}

DateTime? _flowDefaultCreateStartAt(
  List<BoardColumn> columns,
  String columnId,
) {
  if (!_flowIsInProgressColumnForCreate(columns, columnId)) return null;
  return DateTime.now();
}

String _flowWorkItemTypeLabel(WorkItemType type) {
  return switch (type) {
    WorkItemType.goal => 'Goal',
    WorkItemType.project => 'Project',
    WorkItemType.task => 'Task',
    WorkItemType.action => 'Action',
  };
}

String _flowDateOnly(DateTime date) => date.toIso8601String().split('T').first;

class _FlowPreferencesBridge extends ConsumerStatefulWidget {
  const _FlowPreferencesBridge();

  @override
  ConsumerState<_FlowPreferencesBridge> createState() =>
      _FlowPreferencesBridgeState();
}

class _FlowPreferencesBridgeState
    extends ConsumerState<_FlowPreferencesBridge> {
  String? _lastAppliedUserId;

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(boardScopeUserIdProvider);
    final preferences = ref.watch(boardFlowPreferencesProvider).valueOrNull;
    if (preferences == null) return const SizedBox.shrink();

    if (_lastAppliedUserId != userId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(boardFlowVisibleTypesProvider.notifier).state =
            preferences.visibleTypes;
        ref.read(boardFlowMotionEnabledProvider.notifier).state =
            preferences.motionEnabled;
        ref.read(boardFlowMotionSpeedProvider.notifier).state =
            preferences.motionSpeed;
        ref.read(boardFlowSuppressedItemsProvider.notifier).state =
            preferences.suppressedItems;
        ref.read(boardFlowReviewedItemsProvider.notifier).state =
            preferences.reviewedItems;
        _lastAppliedUserId = userId;
      });
    }
    return const SizedBox.shrink();
  }
}

class _FlowEmptyState extends StatelessWidget {
  const _FlowEmptyState({
    required this.multiBoardScope,
    required this.totalTodayCount,
    required this.reviewedTodayCount,
  });

  final bool multiBoardScope;
  final int totalTodayCount;
  final int reviewedTodayCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 240;
        return SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 16 : 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(compact ? 18 : 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.air_rounded,
                        size: compact ? 38 : 46,
                        color: theme.colorScheme.primary,
                      ),
                      SizedBox(height: compact ? 10 : 14),
                      Text(
                        totalTodayCount > 0 &&
                                reviewedTodayCount == totalTodayCount
                            ? 'You already went through everything for today.'
                            : 'Nothing is floating up right now.',
                        style: theme.textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        totalTodayCount > 0 &&
                                reviewedTodayCount == totalTodayCount
                            ? 'Flow will refill tomorrow when the daily review count resets.'
                            : multiBoardScope
                                ? 'There are no task or action items left to review in the current Flow scope today.'
                                : 'There are no task or action items left to review from this board today.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FlowTodayCountPill extends StatelessWidget {
  const _FlowTodayCountPill({required this.remainingTodayCount});

  final int remainingTodayCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.92),
      elevation: 3,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.flag_circle_outlined,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '$remainingTodayCount left today',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<_FlowSlot> _buildCandidateSlots(double width, double height, int count) {
  final shortHeight = height < 520;
  final columns = width >= 1100
      ? 3
      : width >= 720
          ? 3
          : 2;
  final cardWidth = width >= 1100
      ? 280.0
      : width >= 720
          ? 240.0
          : math.min(220.0, (width - 56) / columns);
  const horizontalGap = 18.0;
  final verticalGap = shortHeight ? 14.0 : 18.0;
  final rows = (count / columns).ceil();
  final totalWidth = cardWidth * columns + horizontalGap * (columns - 1);
  final startX = math.max(16.0, (width - totalWidth) / 2);
  final bandTop = shortHeight ? 20.0 : 28.0;
  final cardHeight = width >= 720
      ? 154.0
      : shortHeight
          ? 132.0
          : 146.0;
  final totalHeight = rows * cardHeight + (rows - 1) * verticalGap;
  final availableHeight = math.max(
      shortHeight ? 220.0 : 260.0, height - (shortHeight ? 36.0 : 56.0));
  final startY =
      math.max(bandTop, bandTop + (availableHeight - totalHeight) / 2);

  return [
    for (var index = 0; index < count; index++)
      _FlowSlot(
        left: startX + (index % columns) * (cardWidth + horizontalGap),
        top: startY + (index ~/ columns) * (cardHeight + verticalGap),
        width: cardWidth,
        height: cardHeight,
      ),
  ];
}

class _FlowSlot {
  const _FlowSlot({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}

class _FlowFloatingCard extends StatelessWidget {
  const _FlowFloatingCard({
    super.key,
    required this.candidate,
    required this.position,
    required this.slot,
    required this.accentColor,
    required this.selected,
    required this.showBoardName,
    required this.dimmed,
    required this.motionEnabled,
    required this.onTap,
    required this.onDoubleTap,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  final BoardFlowCandidate candidate;
  final Offset position;
  final _FlowSlot slot;
  final Color accentColor;
  final bool selected;
  final bool showBoardName;
  final bool dimmed;
  final bool motionEnabled;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;

  Duration get _riseDuration {
    return switch (candidate.urgency) {
      BoardFlowUrgency.overdue => const Duration(milliseconds: 760),
      BoardFlowUrgency.today => const Duration(milliseconds: 980),
      BoardFlowUrgency.reminder => const Duration(milliseconds: 1500),
      BoardFlowUrgency.upcoming => const Duration(milliseconds: 1320),
      BoardFlowUrgency.anytime => const Duration(milliseconds: 1640),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compactCard = slot.height <= 138;
    final metadataParts = <String>[
      if (candidate.parentTitle != null) 'Parent: ${candidate.parentTitle}',
      if (showBoardName) candidate.boardName,
    ];
    final scale = switch (candidate.urgency) {
      BoardFlowUrgency.overdue => 1.03,
      BoardFlowUrgency.today => 1.01,
      BoardFlowUrgency.reminder => 0.995,
      BoardFlowUrgency.upcoming => 1.0,
      BoardFlowUrgency.anytime => 0.99,
    };
    final emphasisGlow = switch (candidate.urgency) {
      BoardFlowUrgency.overdue => 0.18,
      BoardFlowUrgency.today => 0.1,
      BoardFlowUrgency.reminder => 0.04,
      BoardFlowUrgency.upcoming => 0.05,
      BoardFlowUrgency.anytime => 0.03,
    };

    final cardChild = GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: slot.width,
        height: slot.height,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected
                ? accentColor.withValues(alpha: 0.7)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
            width: selected ? 1.6 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: emphasisGlow),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Row(
            children: [
              Container(width: 7, color: accentColor),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compactCard ? 12 : 14,
                    compactCard ? 12 : 14,
                    compactCard ? 12 : 14,
                    compactCard ? 10 : 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _FlowTypePill(type: candidate.item.type),
                          const Spacer(),
                          Icon(
                            _urgencyIcon(candidate.urgency),
                            size: 18,
                            color: accentColor,
                          ),
                        ],
                      ),
                      SizedBox(height: compactCard ? 8 : 10),
                      Text(
                        candidate.item.title,
                        maxLines: compactCard ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      if (metadataParts.isNotEmpty) ...[
                        SizedBox(height: compactCard ? 6 : 8),
                        Text(
                          metadataParts.join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        candidate.message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: accentColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Positioned(
      left: position.dx,
      top: position.dy,
      width: slot.width,
      height: slot.height,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 1, end: 0),
        duration: _riseDuration,
        curve: Curves.easeOutCubic,
        builder: (context, value, _) {
          final riseOffset = motionEnabled ? (value * 220.0) : 0.0;
          return Transform.translate(
            offset: Offset(0, riseOffset),
            child: Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: dimmed ? 0.24 : 1,
                child: Draggable<BoardFlowCandidate>(
                  data: candidate,
                  dragAnchorStrategy: pointerDragAnchorStrategy,
                  feedbackOffset: Offset.zero,
                  maxSimultaneousDrags: 1,
                  onDragStarted: onDragStarted,
                  onDragEnd: (_) => onDragEnded(),
                  onDraggableCanceled: (_, __) => onDragEnded(),
                  onDragCompleted: onDragEnded,
                  feedback: Material(
                    color: Colors.transparent,
                    child: Transform.scale(
                      scale: 0.95,
                      child: SizedBox(
                        width: slot.width,
                        child: cardChild,
                      ),
                    ),
                  ),
                  childWhenDragging: Opacity(
                    opacity: 0.08,
                    child: cardChild,
                  ),
                  child: cardChild,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static IconData _urgencyIcon(BoardFlowUrgency urgency) {
    return switch (urgency) {
      BoardFlowUrgency.overdue => Icons.local_fire_department_outlined,
      BoardFlowUrgency.today => Icons.today_outlined,
      BoardFlowUrgency.reminder => Icons.notifications_active_outlined,
      BoardFlowUrgency.upcoming => Icons.upcoming_outlined,
      BoardFlowUrgency.anytime => Icons.adjust_outlined,
    };
  }
}

const _flowCreatePuckDiameter = 76.0;
const _flowCreatePuckItemKey = '__flow-create-puck__';

_FlowSlot _flowCreatePuckSlot() {
  return const _FlowSlot(
    left: 0,
    top: 0,
    width: _flowCreatePuckDiameter,
    height: _flowCreatePuckDiameter,
  );
}

Offset _flowCreatePuckInitialPosition(Size playfieldSize) {
  const inset = 16.0;
  return Offset(
    inset,
    math.max(
      inset,
      playfieldSize.height - _flowCreatePuckDiameter - inset,
    ),
  );
}

class _FlowCreatePuckPayload {
  const _FlowCreatePuckPayload();
}

class _FlowCreatePuck extends StatelessWidget {
  const _FlowCreatePuck({
    required this.dragging,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  final bool dragging;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget puck({double opacity = 1, bool elevated = false}) {
      return Opacity(
        opacity: opacity,
        child: Material(
          color: Colors.transparent,
          child: Container(
            key: const ValueKey('flow-create-puck'),
            width: _flowCreatePuckDiameter,
            height: _flowCreatePuckDiameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primaryContainer,
                  theme.colorScheme.primary.withValues(alpha: 0.94),
                ],
              ),
              border: Border.all(
                color: theme.colorScheme.onPrimaryContainer
                    .withValues(alpha: 0.22),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(
                    alpha: elevated ? 0.30 : 0.18,
                  ),
                  blurRadius: elevated ? 26 : 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_rounded,
                  color: theme.colorScheme.onPrimary,
                  size: 26,
                ),
                const SizedBox(height: 2),
                Text(
                  'New',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Draggable<_FlowCreatePuckPayload>(
      data: const _FlowCreatePuckPayload(),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedbackOffset: Offset.zero,
      maxSimultaneousDrags: 1,
      onDragStarted: onDragStarted,
      onDragEnd: (_) => onDragEnded(),
      onDraggableCanceled: (_, __) => onDragEnded(),
      onDragCompleted: onDragEnded,
      feedback: Transform.scale(
        scale: 0.96,
        child: puck(elevated: true),
      ),
      childWhenDragging: puck(opacity: 0.14),
      child: puck(opacity: dragging ? 0.8 : 1),
    );
  }
}

class _ActiveFlowMalletState {
  const _ActiveFlowMalletState({
    required this.pointer,
    required this.position,
    required this.velocity,
    required this.lastEventSeconds,
  });

  final int pointer;
  final Offset position;
  final Offset velocity;
  final double lastEventSeconds;

  _ActiveFlowMalletState copyWith({
    int? pointer,
    Offset? position,
    Offset? velocity,
    double? lastEventSeconds,
  }) {
    return _ActiveFlowMalletState(
      pointer: pointer ?? this.pointer,
      position: position ?? this.position,
      velocity: velocity ?? this.velocity,
      lastEventSeconds: lastEventSeconds ?? this.lastEventSeconds,
    );
  }
}

class _FlowMalletOverlay extends StatelessWidget {
  const _FlowMalletOverlay({
    required this.position,
    required this.playfieldSize,
    required this.intensity,
  });

  final Offset position;
  final Size playfieldSize;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diameter = 48.0;
    final left = (position.dx - diameter / 2)
        .clamp(0.0, math.max(0.0, playfieldSize.width - diameter))
        .toDouble();
    final top = (position.dy - diameter / 2)
        .clamp(0.0, math.max(0.0, playfieldSize.height - diameter))
        .toDouble();
    final glow = (0.10 + (intensity / 1800)).clamp(0.10, 0.24).toDouble();

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          key: const ValueKey('flow-mallet'),
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary.withValues(alpha: 0.10),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.55),
              width: 1.8,
            ),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: glow),
                blurRadius: 22,
                spreadRadius: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _flowPointHitsAnyCard({
  required Offset point,
  required List<String> itemKeys,
  required List<_FlowSlot> slots,
  required List<Offset> displayedPositions,
}) {
  for (var index = 0; index < itemKeys.length; index++) {
    final rect = _flowRectForPosition(displayedPositions[index], slots[index]);
    if (rect.contains(point)) {
      return true;
    }
  }
  return false;
}

Offset _clampPointToPlayfield(Offset point, Size playfieldSize) {
  return Offset(
    point.dx.clamp(0.0, playfieldSize.width),
    point.dy.clamp(0.0, playfieldSize.height),
  );
}

void _applyFlowMalletImpulse({
  required List<String> itemKeys,
  required List<_FlowSlot> slots,
  required Offset previousMalletPosition,
  required Offset malletPosition,
  required Offset malletVelocity,
  required Size playfieldSize,
  required Map<String, Offset> positions,
  required Map<String, Offset> velocities,
  required Map<String, double> hitCooldowns,
  required double timeSeconds,
}) {
  hitCooldowns.removeWhere((_, expiresAt) => expiresAt <= timeSeconds);

  final speed = malletVelocity.distance;
  if (speed < 70) {
    return;
  }

  const malletRadius = 28.0;
  final malletSweep =
      Rect.fromPoints(previousMalletPosition, malletPosition).inflate(
    malletRadius,
  );

  for (var index = 0; index < itemKeys.length; index++) {
    final itemKey = itemKeys[index];
    if ((hitCooldowns[itemKey] ?? 0) > timeSeconds) {
      continue;
    }

    final currentPosition = positions[itemKey] ?? Offset.zero;
    final currentRect = _flowRectForPosition(currentPosition, slots[index]);
    if (!malletSweep.overlaps(currentRect.inflate(10))) {
      continue;
    }

    final nearestPoint = Offset(
      malletPosition.dx.clamp(currentRect.left, currentRect.right),
      malletPosition.dy.clamp(currentRect.top, currentRect.bottom),
    );
    final awayFromMallet = currentRect.center - nearestPoint;
    final impactDirection = _normalizeOffset(
      awayFromMallet.distance < 0.001
          ? malletVelocity
          : awayFromMallet + (malletVelocity * 0.35),
    );
    final currentVelocity = velocities[itemKey] ?? Offset.zero;
    final impulse = speed.clamp(220.0, 980.0).toDouble();
    final nextVelocity = currentVelocity + impactDirection * impulse;
    velocities[itemKey] = nextVelocity;
    positions[itemKey] = _clampFlowPosition(
      currentPosition + impactDirection * 12.0,
      slots[index],
      playfieldSize,
    );
    hitCooldowns[itemKey] = timeSeconds + 0.09;
  }
}

List<Offset> _resolveFlowCardPositions({
  required List<String> itemKeys,
  required List<_FlowSlot> slots,
  required Size playfieldSize,
  required double timeSeconds,
  Map<String, _FlowCardDodgeLock>? cardDodgeLocks,
  Map<String, _FlowPairDodgeLock>? pairDodgeLocks,
}) {
  if (itemKeys.length < 2) {
    return [
      for (var index = 0; index < itemKeys.length; index++)
        _baseFlowMotionState(
          playfieldSize: playfieldSize,
          slot: slots[index],
          visualIndex: index,
          itemKey: itemKeys[index],
          timeSeconds: timeSeconds,
        ).position,
    ];
  }

  final effectiveCardLocks = cardDodgeLocks ?? <String, _FlowCardDodgeLock>{};
  final effectivePairLocks = pairDodgeLocks ?? <String, _FlowPairDodgeLock>{};
  final positions = <String, Offset>{};
  final velocities = <String, Offset>{};

  for (var index = 0; index < itemKeys.length; index++) {
    final initialState = _baseFlowMotionState(
      playfieldSize: playfieldSize,
      slot: slots[index],
      visualIndex: index,
      itemKey: itemKeys[index],
      timeSeconds: 0,
    );
    positions[itemKeys[index]] = initialState.position;
    velocities[itemKeys[index]] = initialState.velocity;
  }

  final totalSeconds = math.max(0.0, timeSeconds);
  final stepCount = math.max(1, (totalSeconds / (1 / 60)).ceil());
  final stepSeconds = totalSeconds / stepCount;
  for (var step = 0; step < stepCount; step++) {
    _advanceFlowSimulationStep(
      itemKeys: itemKeys,
      slots: slots,
      playfieldSize: playfieldSize,
      positions: positions,
      velocities: velocities,
      cardDodgeLocks: effectiveCardLocks,
      pairDodgeLocks: effectivePairLocks,
      stepSeconds: stepSeconds,
      currentTimeSeconds: step * stepSeconds,
    );
  }

  return [
    for (var index = 0; index < itemKeys.length; index++)
      positions[itemKeys[index]] ?? Offset.zero,
  ];
}

void _advanceFlowSimulationStep({
  required List<String> itemKeys,
  required List<_FlowSlot> slots,
  required Size playfieldSize,
  required Map<String, Offset> positions,
  required Map<String, Offset> velocities,
  required Map<String, _FlowCardDodgeLock> cardDodgeLocks,
  required Map<String, _FlowPairDodgeLock> pairDodgeLocks,
  required double stepSeconds,
  double? currentTimeSeconds,
}) {
  final timeSeconds = currentTimeSeconds ?? 0.0;
  cardDodgeLocks.removeWhere((_, lock) => lock.expiresAtSeconds < timeSeconds);
  pairDodgeLocks.removeWhere((_, lock) => lock.expiresAtSeconds < timeSeconds);

  final stepScale = (stepSeconds * 60).clamp(0.5, 2.0).toDouble();
  for (var index = 0; index < itemKeys.length; index++) {
    final itemKey = itemKeys[index];
    final currentVelocity = velocities[itemKey] ?? Offset.zero;
    final baseVelocity = _seededFlowVelocity(
      visualIndex: index,
      itemKey: itemKey,
    );
    final targetSpeed = baseVelocity.distance;
    final currentSpeed = currentVelocity.distance;
    final direction = currentSpeed < 0.001
        ? _normalizeOffset(baseVelocity)
        : currentVelocity / currentSpeed;
    final nextSpeed = currentSpeed < 0.001
        ? targetSpeed
        : currentSpeed + (targetSpeed - currentSpeed) * (0.03 * stepScale);
    velocities[itemKey] = direction * nextSpeed;
  }

  final interactions = <_FlowDodgeInteraction>[];
  for (var index = 0; index < itemKeys.length; index++) {
    for (var otherIndex = index + 1;
        otherIndex < itemKeys.length;
        otherIndex++) {
      final firstRect = _flowRectForPosition(
        positions[itemKeys[index]] ?? Offset.zero,
        slots[index],
      );
      final secondRect = _flowRectForPosition(
        positions[itemKeys[otherIndex]] ?? Offset.zero,
        slots[otherIndex],
      );
      final overlapX = math.min(firstRect.right, secondRect.right) -
          math.max(firstRect.left, secondRect.left);
      final overlapY = math.min(firstRect.bottom, secondRect.bottom) -
          math.max(firstRect.top, secondRect.top);
      if (overlapX <= 0 || overlapY <= 0) {
        continue;
      }

      final widthRatio = overlapX / math.min(firstRect.width, secondRect.width);
      final heightRatio =
          overlapY / math.min(firstRect.height, secondRect.height);
      if (widthRatio < 0.60 || heightRatio < 0.60) {
        continue;
      }

      final firstVelocity = velocities[itemKeys[index]] ?? Offset.zero;
      final secondVelocity = velocities[itemKeys[otherIndex]] ?? Offset.zero;
      final firstSpeed = firstVelocity.distance;
      final secondSpeed = secondVelocity.distance;
      if (firstSpeed < 0.001 || secondSpeed < 0.001) {
        continue;
      }

      final firstDirection = firstVelocity / firstSpeed;
      final secondDirection = secondVelocity / secondSpeed;
      final similarity = firstDirection.dx * secondDirection.dx +
          firstDirection.dy * secondDirection.dy;
      if (similarity < 0.72) {
        continue;
      }

      final sharedDirection =
          _normalizeOffset(firstDirection + secondDirection);
      final firstProjection = _projectRectCenter(firstRect, sharedDirection);
      final secondProjection = _projectRectCenter(secondRect, sharedDirection);
      final pairKey = _flowPairKey(itemKeys[index], itemKeys[otherIndex]);
      final firstCardLock = cardDodgeLocks[itemKeys[index]];
      final secondCardLock = cardDodgeLocks[itemKeys[otherIndex]];
      final existingLock = pairDodgeLocks[pairKey];
      final dodgedIndex = existingLock != null
          ? (existingLock.dodgedItemKey == itemKeys[index] ? index : otherIndex)
          : firstCardLock != null && secondCardLock == null
              ? index
              : secondCardLock != null && firstCardLock == null
                  ? otherIndex
                  : (firstProjection <= secondProjection ? index : otherIndex);
      final dodgedItemKey = itemKeys[dodgedIndex];
      final stationaryIndex = dodgedIndex == index ? otherIndex : index;
      final stationaryItemKey = itemKeys[stationaryIndex];
      if (cardDodgeLocks[stationaryItemKey] != null &&
          cardDodgeLocks[dodgedItemKey] == null) {
        continue;
      }

      final severity =
          (((math.min(widthRatio, heightRatio) - 0.60) / 0.40).clamp(0.0, 1.0))
              .toDouble();
      final dodgeStrength = severity <= 0
          ? 0.0
          : 0.25 + (0.75 * Curves.easeOutCubic.transform(severity));
      final cross =
          (secondRect.center.dx - firstRect.center.dx) * sharedDirection.dy -
              (secondRect.center.dy - firstRect.center.dy) * sharedDirection.dx;
      final preferredSide = existingLock?.preferredSide ??
          (cross.abs() >= 0.001
              ? (cross.isNegative ? -1.0 : 1.0)
              : (((itemKeys[index].hashCode ^ itemKeys[otherIndex].hashCode) &
                          1) ==
                      0
                  ? 1.0
                  : -1.0));
      final lockedPreferredSide = cardDodgeLocks[dodgedItemKey]?.preferredSide;
      interactions.add(
        _FlowDodgeInteraction(
          firstIndex: index,
          secondIndex: otherIndex,
          dodgedIndex: dodgedIndex,
          sharedDirection: sharedDirection,
          preferredSide: lockedPreferredSide ?? preferredSide,
          dodgeStrength: dodgeStrength,
          overlapScore: widthRatio * heightRatio * similarity,
          pairKey: pairKey,
        ),
      );
    }
  }

  interactions.sort(
    (left, right) => right.overlapScore.compareTo(left.overlapScore),
  );

  final committedIndices = <int>{};
  for (final interaction in interactions) {
    if (committedIndices.contains(interaction.firstIndex) ||
        committedIndices.contains(interaction.secondIndex)) {
      continue;
    }

    final dodgedIndex = interaction.dodgedIndex;
    final stationaryIndex = dodgedIndex == interaction.firstIndex
        ? interaction.secondIndex
        : interaction.firstIndex;
    final dodgedItemKey = itemKeys[dodgedIndex];
    final stationaryItemKey = itemKeys[stationaryIndex];
    final dodgedSlot = slots[dodgedIndex];
    final stationaryRect = _flowRectForPosition(
      positions[stationaryItemKey] ?? Offset.zero,
      slots[stationaryIndex],
    );
    final dodgedPosition = positions[dodgedItemKey] ?? Offset.zero;
    final currentVelocity = velocities[dodgedItemKey] ?? Offset.zero;
    final currentSpeed = math.max(90.0, currentVelocity.distance);

    final targetDirection = [
      interaction.preferredSide,
      -interaction.preferredSide,
    ].map((side) {
      final lateralDirection = Offset(
            -interaction.sharedDirection.dy,
            interaction.sharedDirection.dx,
          ) *
          side;
      return _normalizeOffset(
        interaction.sharedDirection * 0.72 +
            lateralDirection * (0.55 + (0.40 * interaction.dodgeStrength)),
      );
    }).reduce((best, candidate) {
      final bestRect = _flowRectForPosition(
        _clampFlowPosition(
          dodgedPosition + (best * currentSpeed * stepSeconds),
          dodgedSlot,
          playfieldSize,
        ),
        dodgedSlot,
      );
      final candidateRect = _flowRectForPosition(
        _clampFlowPosition(
          dodgedPosition + (candidate * currentSpeed * stepSeconds),
          dodgedSlot,
          playfieldSize,
        ),
        dodgedSlot,
      );
      return _flowOverlapArea(candidateRect, stationaryRect) <
              _flowOverlapArea(bestRect, stationaryRect)
          ? candidate
          : best;
    });

    final desiredVelocity = targetDirection * currentSpeed;
    velocities[dodgedItemKey] = Offset.lerp(
          currentVelocity,
          desiredVelocity,
          (0.16 + (0.18 * interaction.dodgeStrength)) * stepScale,
        ) ??
        desiredVelocity;
    positions[dodgedItemKey] = _clampFlowPosition(
      dodgedPosition +
          (Offset(
                -interaction.sharedDirection.dy,
                interaction.sharedDirection.dx,
              ) *
              interaction.preferredSide *
              (10.0 * interaction.dodgeStrength * stepSeconds)),
      dodgedSlot,
      playfieldSize,
    );
    pairDodgeLocks[interaction.pairKey] = _FlowPairDodgeLock(
      dodgedItemKey: dodgedItemKey,
      preferredSide: interaction.preferredSide,
      expiresAtSeconds: timeSeconds + 0.9,
    );
    cardDodgeLocks[dodgedItemKey] = _FlowCardDodgeLock(
      preferredSide: interaction.preferredSide,
      expiresAtSeconds: timeSeconds + 1.15,
    );
    committedIndices.add(interaction.firstIndex);
    committedIndices.add(interaction.secondIndex);
  }

  for (var index = 0; index < itemKeys.length; index++) {
    final itemKey = itemKeys[index];
    final moved = _moveFlowCardWithinBounds(
      position: positions[itemKey] ?? Offset.zero,
      velocity: velocities[itemKey] ?? Offset.zero,
      slot: slots[index],
      playfieldSize: playfieldSize,
      stepSeconds: stepSeconds,
    );
    positions[itemKey] = moved.position;
    velocities[itemKey] = moved.velocity;
  }
}

class _FlowDodgeInteraction {
  const _FlowDodgeInteraction({
    required this.firstIndex,
    required this.secondIndex,
    required this.dodgedIndex,
    required this.sharedDirection,
    required this.preferredSide,
    required this.dodgeStrength,
    required this.overlapScore,
    required this.pairKey,
  });

  final int firstIndex;
  final int secondIndex;
  final int dodgedIndex;
  final Offset sharedDirection;
  final double preferredSide;
  final double dodgeStrength;
  final double overlapScore;
  final String pairKey;
}

class _FlowPairDodgeLock {
  const _FlowPairDodgeLock({
    required this.dodgedItemKey,
    required this.preferredSide,
    required this.expiresAtSeconds,
  });

  final String dodgedItemKey;
  final double preferredSide;
  final double expiresAtSeconds;
}

class _FlowCardDodgeLock {
  const _FlowCardDodgeLock({
    required this.preferredSide,
    required this.expiresAtSeconds,
  });

  final double preferredSide;
  final double expiresAtSeconds;
}

Rect _flowRectForPosition(Offset position, _FlowSlot slot) {
  return Rect.fromLTWH(position.dx, position.dy, slot.width, slot.height);
}

double _flowOverlapArea(Rect firstRect, Rect secondRect) {
  final overlapX = math.max(
    0.0,
    math.min(firstRect.right, secondRect.right) -
        math.max(firstRect.left, secondRect.left),
  );
  final overlapY = math.max(
    0.0,
    math.min(firstRect.bottom, secondRect.bottom) -
        math.max(firstRect.top, secondRect.top),
  );
  return overlapX * overlapY;
}

Offset _clampFlowPosition(
  Offset position,
  _FlowSlot slot,
  Size playfieldSize,
) {
  const margin = 0.0;
  final minX = margin;
  final maxX = math.max(minX, playfieldSize.width - slot.width - margin);
  final minY = margin;
  final maxY = math.max(minY, playfieldSize.height - slot.height - margin);
  return Offset(
    position.dx.clamp(minX, maxX),
    position.dy.clamp(minY, maxY),
  );
}

class _FlowMotionState {
  const _FlowMotionState({
    required this.position,
    required this.velocity,
  });

  final Offset position;
  final Offset velocity;
}

class _ReflectedAxisMotion {
  const _ReflectedAxisMotion({
    required this.position,
    required this.directionMultiplier,
  });

  final double position;
  final double directionMultiplier;
}

_FlowMotionState _baseFlowMotionState({
  required Size playfieldSize,
  required _FlowSlot slot,
  required int visualIndex,
  required String itemKey,
  required double timeSeconds,
}) {
  const margin = 0.0;
  final availableWidth =
      math.max(0.0, playfieldSize.width - slot.width - margin * 2);
  final availableHeight =
      math.max(0.0, playfieldSize.height - slot.height - margin * 2);

  if (availableWidth == 0 || availableHeight == 0) {
    return const _FlowMotionState(
      position: Offset.zero,
      velocity: Offset.zero,
    );
  }

  final seed = itemKey.hashCode ^ (visualIndex * 131);
  final startX = availableWidth * _unitSeed(seed, 0);
  final startY = availableHeight * _unitSeed(seed, 1);
  final seededVelocity = _seededFlowVelocity(
    visualIndex: visualIndex,
    itemKey: itemKey,
  );
  final reflectedX = _reflectAxisMotion(
    startX + seededVelocity.dx * timeSeconds,
    availableWidth,
  );
  final reflectedY = _reflectAxisMotion(
    startY + seededVelocity.dy * timeSeconds,
    availableHeight,
  );
  return _FlowMotionState(
    position: Offset(
      margin + reflectedX.position,
      margin + reflectedY.position,
    ),
    velocity: Offset(
      seededVelocity.dx * reflectedX.directionMultiplier,
      seededVelocity.dy * reflectedY.directionMultiplier,
    ),
  );
}

Offset _seededFlowVelocity({
  required int visualIndex,
  required String itemKey,
}) {
  final seed = itemKey.hashCode ^ (visualIndex * 131);
  final velocityX =
      (70 + (_unitSeed(seed, 2) * 70)) * (visualIndex.isEven ? 1 : -1);
  final velocityY =
      (58 + (_unitSeed(seed, 3) * 64)) * (visualIndex % 3 == 0 ? -1 : 1);
  return Offset(velocityX, velocityY);
}

_FlowMotionState _moveFlowCardWithinBounds({
  required Offset position,
  required Offset velocity,
  required _FlowSlot slot,
  required Size playfieldSize,
  required double stepSeconds,
}) {
  final maxX = math.max(0.0, playfieldSize.width - slot.width);
  final maxY = math.max(0.0, playfieldSize.height - slot.height);
  var nextX = position.dx + velocity.dx * stepSeconds;
  var nextY = position.dy + velocity.dy * stepSeconds;
  var nextVelocityX = velocity.dx;
  var nextVelocityY = velocity.dy;

  if (nextX < 0) {
    nextX = -nextX;
    nextVelocityX = velocity.dx.abs();
  } else if (nextX > maxX) {
    nextX = maxX - (nextX - maxX);
    nextVelocityX = -velocity.dx.abs();
  }

  if (nextY < 0) {
    nextY = -nextY;
    nextVelocityY = velocity.dy.abs();
  } else if (nextY > maxY) {
    nextY = maxY - (nextY - maxY);
    nextVelocityY = -velocity.dy.abs();
  }

  return _FlowMotionState(
    position: Offset(
      nextX.clamp(0.0, maxX),
      nextY.clamp(0.0, maxY),
    ),
    velocity: Offset(nextVelocityX, nextVelocityY),
  );
}

class FlowCardDebugState {
  const FlowCardDebugState({
    required this.rect,
    required this.velocity,
  });

  final Rect rect;
  final Offset velocity;
}

List<FlowCardDebugState> resolveFlowCardDebugStatesForTesting({
  required Size playfieldSize,
  required List<Size> cardSizes,
  required List<String> itemKeys,
  required double timeSeconds,
}) {
  final slots = [
    for (final size in cardSizes)
      _FlowSlot(
        left: 0,
        top: 0,
        width: size.width,
        height: size.height,
      ),
  ];
  final positions = _resolveFlowCardPositions(
    itemKeys: itemKeys,
    slots: slots,
    playfieldSize: playfieldSize,
    timeSeconds: timeSeconds,
  );
  return [
    for (var index = 0; index < slots.length; index++)
      FlowCardDebugState(
        rect: _flowRectForPosition(positions[index], slots[index]),
        velocity: _baseFlowMotionState(
          playfieldSize: playfieldSize,
          slot: slots[index],
          visualIndex: index,
          itemKey: itemKeys[index],
          timeSeconds: timeSeconds,
        ).velocity,
      ),
  ];
}

FlowCardDebugState resolveFlowCardDebugStateAfterMalletForTesting({
  required Size playfieldSize,
  required Size cardSize,
  required String itemKey,
  required Offset initialPosition,
  required Offset initialVelocity,
  required Offset previousMalletPosition,
  required Offset malletPosition,
  required Offset malletVelocity,
}) {
  final slot = _FlowSlot(
    left: 0,
    top: 0,
    width: cardSize.width,
    height: cardSize.height,
  );
  final positions = <String, Offset>{itemKey: initialPosition};
  final velocities = <String, Offset>{itemKey: initialVelocity};
  _applyFlowMalletImpulse(
    itemKeys: <String>[itemKey],
    slots: <_FlowSlot>[slot],
    previousMalletPosition: previousMalletPosition,
    malletPosition: malletPosition,
    malletVelocity: malletVelocity,
    playfieldSize: playfieldSize,
    positions: positions,
    velocities: velocities,
    hitCooldowns: <String, double>{},
    timeSeconds: 1.0,
  );
  return FlowCardDebugState(
    rect: _flowRectForPosition(positions[itemKey] ?? Offset.zero, slot),
    velocity: velocities[itemKey] ?? Offset.zero,
  );
}

FlowCardDebugState resolveFlowCreatePuckDebugStateForTesting({
  required Size playfieldSize,
  required double timeSeconds,
}) {
  final slot = _flowCreatePuckSlot();
  var position = _flowCreatePuckInitialPosition(playfieldSize);
  var velocity =
      _seededFlowVelocity(visualIndex: 97, itemKey: _flowCreatePuckItemKey);

  final stepCount = math.max(1, (timeSeconds * 60).round());
  final stepSeconds = timeSeconds / stepCount;
  for (var step = 0; step < stepCount; step++) {
    final speed = velocity.distance;
    final targetSpeed = _seededFlowVelocity(
      visualIndex: 97,
      itemKey: _flowCreatePuckItemKey,
    ).distance;
    final direction =
        speed < 0.001 ? const Offset(1, 0) : _normalizeOffset(velocity);
    final nextSpeed =
        speed < 0.001 ? targetSpeed : speed + (targetSpeed - speed) * 0.03;
    velocity = direction * nextSpeed;
    final moved = _moveFlowCardWithinBounds(
      position: position,
      velocity: velocity,
      slot: slot,
      playfieldSize: playfieldSize,
      stepSeconds: stepSeconds,
    );
    position = moved.position;
    velocity = moved.velocity;
  }

  return FlowCardDebugState(
    rect: _flowRectForPosition(position, slot),
    velocity: velocity,
  );
}

double _unitSeed(int seed, int salt) {
  final value = (seed + (salt * 104729)).abs() % 1000;
  return value / 999.0;
}

_ReflectedAxisMotion _reflectAxisMotion(double value, double max) {
  if (max <= 0) {
    return const _ReflectedAxisMotion(
      position: 0,
      directionMultiplier: 1,
    );
  }
  final period = max * 2;
  var wrapped = value % period;
  if (wrapped < 0) wrapped += period;
  if (wrapped <= max) {
    return _ReflectedAxisMotion(position: wrapped, directionMultiplier: 1);
  }
  return _ReflectedAxisMotion(
    position: period - wrapped,
    directionMultiplier: -1,
  );
}

Offset _normalizeOffset(Offset value) {
  final distance = value.distance;
  if (distance < 0.001) {
    return const Offset(1, 0);
  }
  return value / distance;
}

double _projectRectCenter(Rect rect, Offset direction) {
  return rect.center.dx * direction.dx + rect.center.dy * direction.dy;
}

String _flowPairKey(String firstItemKey, String secondItemKey) {
  return firstItemKey.compareTo(secondItemKey) <= 0
      ? '$firstItemKey||$secondItemKey'
      : '$secondItemKey||$firstItemKey';
}

class _FlowTypePill extends StatelessWidget {
  const _FlowTypePill({required this.type});

  final WorkItemType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (type) {
      WorkItemType.task => 'Task',
      WorkItemType.action => 'Action',
      WorkItemType.goal => 'Goal',
      WorkItemType.project => 'Project',
    };
    final icon = switch (type) {
      WorkItemType.task => Icons.checklist_rtl_outlined,
      WorkItemType.action => Icons.bolt_outlined,
      WorkItemType.goal => Icons.flag_outlined,
      WorkItemType.project => Icons.route_outlined,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

class _FlowActionRing extends StatelessWidget {
  const _FlowActionRing({
    required this.playfieldSize,
    required this.onDoNow,
    required this.onSchedule,
    required this.onMoveColumn,
    required this.onDone,
    required this.onNotNow,
  });

  final Size playfieldSize;
  final VoidCallback onDoNow;
  final VoidCallback onSchedule;
  final VoidCallback onMoveColumn;
  final VoidCallback onDone;
  final VoidCallback onNotNow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = playfieldSize.shortestSide < 430;
    final targetSize = compact ? 86.0 : 98.0;
    final ringRadius = compact ? 108.0 : 126.0;
    final ringCenter = Offset(
      playfieldSize.width / 2,
      playfieldSize.height * (compact ? 0.58 : 0.55),
    );

    Offset positionFor(double dx, double dy) {
      return Offset(ringCenter.dx + dx, ringCenter.dy + dy);
    }

    Widget positionedTarget({
      required Offset offset,
      required String label,
      required IconData icon,
      required Color color,
      required String targetKey,
      required VoidCallback onAccept,
    }) {
      final left = (offset.dx - targetSize / 2)
          .clamp(8.0, playfieldSize.width - targetSize - 8.0)
          .toDouble();
      final top = (offset.dy - targetSize / 2)
          .clamp(8.0, playfieldSize.height - targetSize - 8.0)
          .toDouble();
      return Positioned(
        left: left,
        top: top,
        child: DragTarget<BoardFlowCandidate>(
          onWillAcceptWithDetails: (_) => true,
          onAcceptWithDetails: (_) => onAccept(),
          builder: (context, candidateData, rejectedData) {
            final active = candidateData.isNotEmpty;
            return AnimatedScale(
              scale: active ? 1.06 : 1,
              duration: const Duration(milliseconds: 120),
              child: Material(
                key: ValueKey(targetKey),
                elevation: active ? 10 : 4,
                color: color.withValues(alpha: active ? 0.22 : 0.14),
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  width: targetSize,
                  height: targetSize,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: color.withValues(alpha: active ? 0.9 : 0.5),
                      width: active ? 1.8 : 1.2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: color),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
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

    return IgnorePointer(
      ignoring: false,
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.08),
            ),
          ),
          positionedTarget(
            offset: positionFor(0, -ringRadius),
            label: 'Schedule',
            icon: Icons.event_outlined,
            color: theme.colorScheme.primary,
            targetKey: 'flow-target-schedule',
            onAccept: onSchedule,
          ),
          positionedTarget(
            offset: positionFor(-ringRadius * 0.85, -ringRadius * 0.36),
            label: 'Do now',
            icon: Icons.play_circle_outline,
            color: const Color(0xFF1C8B5A),
            targetKey: 'flow-target-do-now',
            onAccept: onDoNow,
          ),
          positionedTarget(
            offset: positionFor(-ringRadius * 0.85, ringRadius * 0.54),
            label: 'Move\ncolumn',
            icon: Icons.swap_horiz_outlined,
            color: theme.colorScheme.secondary,
            targetKey: 'flow-target-move-column',
            onAccept: onMoveColumn,
          ),
          positionedTarget(
            offset: positionFor(ringRadius * 0.85, -ringRadius * 0.36),
            label: 'Done',
            icon: Icons.task_alt_outlined,
            color: const Color(0xFF0F8A5F),
            targetKey: 'flow-target-done',
            onAccept: onDone,
          ),
          positionedTarget(
            offset: positionFor(ringRadius * 0.85, ringRadius * 0.54),
            label: 'Dismiss\ntoday',
            icon: Icons.visibility_off_outlined,
            color: theme.colorScheme.tertiary,
            targetKey: 'flow-target-not-now',
            onAccept: onNotNow,
          ),
        ],
      ),
    );
  }
}

class _FlowCreateRing extends StatelessWidget {
  const _FlowCreateRing({
    required this.playfieldSize,
    required this.onTask,
    required this.onAction,
    required this.onProject,
    required this.onGoal,
    required this.onCapture,
  });

  final Size playfieldSize;
  final VoidCallback onTask;
  final VoidCallback onAction;
  final VoidCallback onProject;
  final VoidCallback onGoal;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = playfieldSize.shortestSide < 430;
    final targetSize = compact ? 86.0 : 98.0;
    final ringRadius = compact ? 108.0 : 126.0;
    final ringCenter = Offset(
      playfieldSize.width / 2,
      playfieldSize.height * (compact ? 0.58 : 0.55),
    );

    Offset positionFor(double dx, double dy) {
      return Offset(ringCenter.dx + dx, ringCenter.dy + dy);
    }

    Widget positionedTarget({
      required Offset offset,
      required String label,
      required IconData icon,
      required Color color,
      required String targetKey,
      required VoidCallback onAccept,
    }) {
      final left = (offset.dx - targetSize / 2)
          .clamp(8.0, playfieldSize.width - targetSize - 8.0)
          .toDouble();
      final top = (offset.dy - targetSize / 2)
          .clamp(8.0, playfieldSize.height - targetSize - 8.0)
          .toDouble();
      return Positioned(
        left: left,
        top: top,
        child: DragTarget<_FlowCreatePuckPayload>(
          onWillAcceptWithDetails: (_) => true,
          onAcceptWithDetails: (_) => onAccept(),
          builder: (context, candidateData, rejectedData) {
            final active = candidateData.isNotEmpty;
            return AnimatedScale(
              scale: active ? 1.06 : 1,
              duration: const Duration(milliseconds: 120),
              child: Material(
                key: ValueKey(targetKey),
                elevation: active ? 10 : 4,
                color: color.withValues(alpha: active ? 0.22 : 0.14),
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  width: targetSize,
                  height: targetSize,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: color.withValues(alpha: active ? 0.9 : 0.5),
                      width: active ? 1.8 : 1.2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: color),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
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

    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.08),
          ),
        ),
        positionedTarget(
          offset: positionFor(0, -ringRadius),
          label: 'Task',
          icon: Icons.checklist_rtl_outlined,
          color: theme.colorScheme.primary,
          targetKey: 'flow-create-target-task',
          onAccept: onTask,
        ),
        positionedTarget(
          offset: positionFor(-ringRadius * 0.85, -ringRadius * 0.36),
          label: 'Action',
          icon: Icons.bolt_outlined,
          color: const Color(0xFF1C8B5A),
          targetKey: 'flow-create-target-action',
          onAccept: onAction,
        ),
        positionedTarget(
          offset: positionFor(-ringRadius * 0.85, ringRadius * 0.54),
          label: 'Project',
          icon: Icons.route_outlined,
          color: theme.colorScheme.secondary,
          targetKey: 'flow-create-target-project',
          onAccept: onProject,
        ),
        positionedTarget(
          offset: positionFor(ringRadius * 0.85, -ringRadius * 0.36),
          label: 'Goal',
          icon: Icons.flag_outlined,
          color: const Color(0xFF0F8A5F),
          targetKey: 'flow-create-target-goal',
          onAccept: onGoal,
        ),
        positionedTarget(
          offset: positionFor(ringRadius * 0.85, ringRadius * 0.54),
          label: 'Capture',
          icon: Icons.inbox_outlined,
          color: theme.colorScheme.tertiary,
          targetKey: 'flow-create-target-capture',
          onAccept: onCapture,
        ),
      ],
    );
  }
}

class _FlowRequiredDateField extends StatelessWidget {
  const _FlowRequiredDateField({
    required this.label,
    required this.value,
    required this.onPick,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final dateValue = value;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              dateValue == null ? 'Required' : _flowDateOnly(dateValue),
            ),
          ),
          IconButton(
            tooltip: 'Pick $label',
            onPressed: onPick,
            icon: const Icon(Icons.calendar_today),
          ),
        ],
      ),
    );
  }
}

class _FlowPlayfieldPainter extends CustomPainter {
  const _FlowPlayfieldPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final path = Path();
    final bandTop = size.height * 0.18;
    final bandBottom = size.height * 0.82;
    path.moveTo(24, bandTop);
    path.quadraticBezierTo(
        size.width * 0.5, bandTop - 24, size.width - 24, bandTop);
    path.moveTo(24, bandBottom);
    path.quadraticBezierTo(
      size.width * 0.5,
      bandBottom + 24,
      size.width - 24,
      bandBottom,
    );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FlowPlayfieldPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _FlowFeedbackBar extends ConsumerStatefulWidget {
  const _FlowFeedbackBar({required this.message});

  final WorkspaceFeedbackMessage message;

  @override
  ConsumerState<_FlowFeedbackBar> createState() => _FlowFeedbackBarState();
}

class _FlowFeedbackBarState extends ConsumerState<_FlowFeedbackBar> {
  Timer? _dismissTimer;

  Duration get _remaining {
    final remaining = widget.message.expiresAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  void initState() {
    super.initState();
    _scheduleDismiss();
  }

  @override
  void didUpdateWidget(covariant _FlowFeedbackBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.feedbackId != widget.message.feedbackId) {
      _scheduleDismiss();
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  void _scheduleDismiss() {
    _dismissTimer?.cancel();
    final remaining = _remaining;
    if (remaining == Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(boardControllerProvider).dismissWorkspaceFeedback(
              widget.message.feedbackId,
            );
      });
      return;
    }
    _dismissTimer = Timer(remaining, () {
      if (!mounted) return;
      ref.read(boardControllerProvider).dismissWorkspaceFeedback(
            widget.message.feedbackId,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = switch (widget.message.severity) {
      WorkspaceFeedbackSeverity.info => Icons.info_outline,
      WorkspaceFeedbackSeverity.success => Icons.check_circle_outline,
      WorkspaceFeedbackSeverity.error => Icons.error_outline,
    };
    final accentColor = switch (widget.message.severity) {
      WorkspaceFeedbackSeverity.info => theme.colorScheme.primary,
      WorkspaceFeedbackSeverity.success => const Color(0xFF1C8B5A),
      WorkspaceFeedbackSeverity.error => theme.colorScheme.error,
    };

    return SafeArea(
      top: false,
      child: Material(
        key: const ValueKey('flow-feedback-bar'),
        elevation: 8,
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Icon(icon, color: accentColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.message.message,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              IconButton(
                tooltip: 'Dismiss feedback',
                onPressed: () {
                  ref.read(boardControllerProvider).dismissWorkspaceFeedback(
                        widget.message.feedbackId,
                      );
                },
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlowPendingUndoBar extends ConsumerStatefulWidget {
  const _FlowPendingUndoBar({required this.operation});

  final BoardUndoOperation operation;

  @override
  ConsumerState<_FlowPendingUndoBar> createState() =>
      _FlowPendingUndoBarState();
}

class _FlowPendingUndoBarState extends ConsumerState<_FlowPendingUndoBar> {
  Timer? _dismissTimer;

  Duration get _remaining {
    final remaining = widget.operation.expiresAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  void initState() {
    super.initState();
    _scheduleDismiss();
  }

  @override
  void didUpdateWidget(covariant _FlowPendingUndoBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.operation.operationId != widget.operation.operationId) {
      _scheduleDismiss();
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  void _scheduleDismiss() {
    _dismissTimer?.cancel();
    final remaining = _remaining;
    if (remaining == Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(boardControllerProvider).clearPendingUndo(
              operationId: widget.operation.operationId,
            );
      });
      return;
    }
    _dismissTimer = Timer(remaining, () {
      if (!mounted) return;
      ref.read(boardControllerProvider).clearPendingUndo(
            operationId: widget.operation.operationId,
          );
    });
  }

  Future<void> _undo() async {
    await ref.read(boardControllerProvider).undoPendingOperation();
  }

  void _dismiss() {
    ref.read(boardControllerProvider).clearPendingUndo(
          operationId: widget.operation.operationId,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = _remaining;
    final progressDuration = remaining == Duration.zero
        ? const Duration(milliseconds: 1)
        : remaining;

    return SafeArea(
      top: false,
      child: Material(
        key: const ValueKey('flow-pending-undo-bar'),
        elevation: 8,
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: TweenAnimationBuilder<double>(
            key: ValueKey(widget.operation.operationId),
            tween: Tween<double>(begin: 1, end: 0),
            duration: progressDuration,
            curve: Curves.linear,
            builder: (context, value, child) {
              final secondsLeft = math.max(
                0,
                (progressDuration.inMilliseconds * value / 1000).ceil(),
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.undo_outlined, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.operation.message,
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                secondsLeft > 0
                                    ? 'Undo available for ${secondsLeft}s'
                                    : 'Undo expiring',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _undo,
                          child: const Text('Undo'),
                        ),
                        IconButton(
                          tooltip: 'Dismiss undo',
                          onPressed: _dismiss,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  LinearProgressIndicator(
                    minHeight: 3,
                    value: value.clamp(0, 1),
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
