import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/help/app_help.dart';
import '../../../core/help/app_help_controller.dart';
import '../../../core/help/app_help_widgets.dart';
import '../domain/models/board_calendar.dart';
import '../domain/models/board_calendar_preferences.dart';
import '../domain/models/work_item.dart';

enum _CalendarUnscheduledTrayState {
  peek,
  open,
}

const _calendarToolbarHelpSpec = AppHelpTargetSpec(
  id: AppHelpTargetIds.calendarToolbar,
  title: 'Calendar toolbar',
  description:
      'This is where you move through time and switch between Month, Week, and Day.',
  whenToUse:
      'Use it whenever you want a broader overview, a closer look, or a fast jump back to today.',
  whatHappens:
      'Previous and Next move the current date range, Today recenters the calendar, and the subview chips change how much detail you see.',
  icon: Icons.calendar_today_outlined,
  tourId: AppHelpTourId.calendar,
);

const _calendarSurfaceHelpSpec = AppHelpTargetSpec(
  id: AppHelpTargetIds.calendarSurface,
  title: 'Calendar surface',
  description: 'This is the main date surface where scheduled work appears.',
  whenToUse:
      'Use it when you want to see what lands on a date, open a busy day, or drag work onto a new due date.',
  whatHappens:
      'Month gives you a lighter overview, while Week and Day show a denser agenda-style view of the same dated work.',
  icon: Icons.date_range_outlined,
  tourId: AppHelpTourId.calendar,
);

const _calendarTrayHelpSpec = AppHelpTargetSpec(
  id: AppHelpTargetIds.calendarUnscheduledTray,
  title: 'Unscheduled tray',
  description:
      'The tray keeps undated items nearby without taking over the calendar.',
  whenToUse:
      'Use it when you want to pull in work that is still floating around without a date.',
  whatHappens:
      'You can open the tray, browse unscheduled items, drag them onto a date, or use Pick date when dragging is not what you want.',
  icon: Icons.vertical_align_top_outlined,
  tourId: AppHelpTourId.calendar,
);

class BoardCalendarView extends ConsumerStatefulWidget {
  const BoardCalendarView({
    super.key,
    required this.subview,
    required this.anchorDate,
    required this.calendarSnapshot,
    required this.accentColorValuesByItemKey,
    required this.showUnscheduled,
    required this.multiBoardScope,
    required this.focusedItemId,
    required this.selectedItemIds,
    required this.canModifyItemsByBoardId,
    required this.onAnchorDateChanged,
    required this.onSubviewChanged,
    required this.onSelectItem,
    required this.onOpenItemDetails,
    required this.onMoveDueDate,
  });

  final BoardCalendarSubview subview;
  final DateTime anchorDate;
  final BoardCalendarSnapshot calendarSnapshot;
  final Map<String, int> accentColorValuesByItemKey;
  final bool showUnscheduled;
  final bool multiBoardScope;
  final String? focusedItemId;
  final Set<String> selectedItemIds;
  final Map<String, bool> canModifyItemsByBoardId;
  final ValueChanged<DateTime> onAnchorDateChanged;
  final ValueChanged<BoardCalendarSubview> onSubviewChanged;
  final ValueChanged<WorkItem> onSelectItem;
  final ValueChanged<WorkItem> onOpenItemDetails;
  final Future<void> Function(WorkItem item, DateTime date) onMoveDueDate;

  @override
  ConsumerState<BoardCalendarView> createState() => _BoardCalendarViewState();
}

class _BoardCalendarViewState extends ConsumerState<BoardCalendarView> {
  static const double _trayPeekHeight = 92;
  static const double _calendarSwipeDistanceThreshold = 72;
  static const double _calendarSwipeDirectionBias = 1.2;
  static const double _calendarSwipeVelocityThreshold = 350;
  static const Duration _calendarSwipeMaxDuration = Duration(milliseconds: 700);

  _CalendarUnscheduledTrayState _trayState = _CalendarUnscheduledTrayState.peek;
  int? _activeSwipePointer;
  Offset? _swipeStartPosition;
  Offset? _swipeLatestPosition;
  DateTime? _swipeStartedAt;
  bool _swipeNavigationConsumed = false;
  double _swipeActiveRegionMaxY = double.infinity;

  bool get _showTray =>
      widget.showUnscheduled &&
      widget.calendarSnapshot.unscheduledItems.isNotEmpty;

  @override
  void didUpdateWidget(covariant BoardCalendarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_showTray && _trayState != _CalendarUnscheduledTrayState.peek) {
      _trayState = _CalendarUnscheduledTrayState.peek;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTourStep = ref.watch(appHelpCurrentTourStepProvider);
    final walkthroughTrayRequested =
        currentTourStep?.targetId == AppHelpTargetIds.calendarUnscheduledTray;
    final showTray = widget.showUnscheduled &&
        (widget.calendarSnapshot.unscheduledItems.isNotEmpty ||
            walkthroughTrayRequested);
    final effectiveTrayState = walkthroughTrayRequested && showTray
        ? _CalendarUnscheduledTrayState.open
        : _trayState;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        final trayOpenHeight = _trayOpenHeight(viewportHeight);
        final trayHeight =
            effectiveTrayState == _CalendarUnscheduledTrayState.open && showTray
                ? trayOpenHeight
                : (showTray ? _trayPeekHeight : 0.0);
        final reservedBottomSpace = showTray ? _trayPeekHeight + 12 : 0.0;
        final calendarSurfaceExtent =
            _calendarSurfaceExtent(viewportHeight, reservedBottomSpace);
        _swipeActiveRegionMaxY = viewportHeight - trayHeight;

        final calendarSurface = switch (widget.subview) {
          BoardCalendarSubview.month => _MonthCalendarView(
              anchorDate: widget.anchorDate,
              calendarSnapshot: widget.calendarSnapshot,
              accentColorValuesByItemKey: widget.accentColorValuesByItemKey,
              multiBoardScope: widget.multiBoardScope,
              focusedItemId: widget.focusedItemId,
              selectedItemIds: widget.selectedItemIds,
              canModifyItemsByBoardId: widget.canModifyItemsByBoardId,
              onSelectItem: widget.onSelectItem,
              onOpenItemDetails: widget.onOpenItemDetails,
              onMoveDueDate: widget.onMoveDueDate,
            ),
          BoardCalendarSubview.week => _WeekCalendarView(
              anchorDate: widget.anchorDate,
              calendarSnapshot: widget.calendarSnapshot,
              accentColorValuesByItemKey: widget.accentColorValuesByItemKey,
              multiBoardScope: widget.multiBoardScope,
              focusedItemId: widget.focusedItemId,
              selectedItemIds: widget.selectedItemIds,
              canModifyItemsByBoardId: widget.canModifyItemsByBoardId,
              onSelectItem: widget.onSelectItem,
              onOpenItemDetails: widget.onOpenItemDetails,
              onMoveDueDate: widget.onMoveDueDate,
            ),
          BoardCalendarSubview.day => _DayCalendarView(
              selectedDate: _dateOnly(widget.anchorDate),
              calendarSnapshot: widget.calendarSnapshot,
              accentColorValuesByItemKey: widget.accentColorValuesByItemKey,
              multiBoardScope: widget.multiBoardScope,
              focusedItemId: widget.focusedItemId,
              selectedItemIds: widget.selectedItemIds,
              canModifyItemsByBoardId: widget.canModifyItemsByBoardId,
              onSelectItem: widget.onSelectItem,
              onOpenItemDetails: widget.onOpenItemDetails,
              onMoveDueDate: widget.onMoveDueDate,
            ),
        };
        return GestureDetector(
          key: const ValueKey('calendar-swipe-surface'),
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: _handleSwipeDragEnd,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _handleSwipePointerDown,
            onPointerMove: _handleSwipePointerMove,
            onPointerUp: _handleSwipePointerUp,
            onPointerCancel: _handleSwipePointerCancel,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: AppHelpTarget(
                          spec: _calendarToolbarHelpSpec,
                          borderRadius: BorderRadius.circular(18),
                          child: _CalendarToolbar(
                            subview: widget.subview,
                            anchorDate: widget.anchorDate,
                            onAnchorDateChanged: widget.onAnchorDateChanged,
                            onSubviewChanged: widget.onSubviewChanged,
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 10)),
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _CalendarSurfaceDelegate(
                          extent: calendarSurfaceExtent,
                          child: AppHelpTarget(
                            spec: _calendarSurfaceHelpSpec,
                            borderRadius: BorderRadius.circular(24),
                            child: calendarSurface,
                          ),
                        ),
                      ),
                      if (showTray)
                        SliverToBoxAdapter(
                          child: SizedBox(height: reservedBottomSpace),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 16)),
                    ],
                  ),
                ),
                if (showTray)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: AppHelpTarget(
                      spec: _calendarTrayHelpSpec,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      child: _CalendarUnscheduledTray(
                        height: trayHeight,
                        isOpen: effectiveTrayState ==
                            _CalendarUnscheduledTrayState.open,
                        itemCount:
                            widget.calendarSnapshot.unscheduledItems.length,
                        unscheduledItems:
                            widget.calendarSnapshot.unscheduledItems,
                        accentColorValuesByItemKey:
                            widget.accentColorValuesByItemKey,
                        multiBoardScope: widget.multiBoardScope,
                        focusedItemId: widget.focusedItemId,
                        selectedItemIds: widget.selectedItemIds,
                        canModifyItemsByBoardId: widget.canModifyItemsByBoardId,
                        onToggle: () {
                          setState(() {
                            _trayState =
                                _trayState == _CalendarUnscheduledTrayState.open
                                    ? _CalendarUnscheduledTrayState.peek
                                    : _CalendarUnscheduledTrayState.open;
                          });
                        },
                        onSelectItem: widget.onSelectItem,
                        onOpenItemDetails: widget.onOpenItemDetails,
                        onMoveDueDate: widget.onMoveDueDate,
                        onStartDrag: () {
                          if (_trayState ==
                              _CalendarUnscheduledTrayState.open) {
                            setState(() {
                              _trayState = _CalendarUnscheduledTrayState.peek;
                            });
                          }
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  double _calendarSurfaceExtent(double viewportHeight, double reservedBottom) {
    final availableHeight = math.max(220.0, viewportHeight - reservedBottom);
    final minExtent = switch (widget.subview) {
      BoardCalendarSubview.month => 404.0,
      BoardCalendarSubview.week => 360.0,
      BoardCalendarSubview.day => 320.0,
    };
    final maxExtent = math.max(minExtent, viewportHeight - 8);
    return availableHeight.clamp(minExtent, maxExtent).toDouble();
  }

  double _trayOpenHeight(double viewportHeight) {
    return (viewportHeight * 0.42).clamp(280.0, 420.0).toDouble();
  }

  void _handleSwipePointerDown(PointerDownEvent event) {
    if (_activeSwipePointer != null) return;
    if (event.localPosition.dy > _swipeActiveRegionMaxY) return;
    _activeSwipePointer = event.pointer;
    _swipeStartPosition = event.position;
    _swipeLatestPosition = event.position;
    _swipeStartedAt = DateTime.now();
    _swipeNavigationConsumed = false;
  }

  void _handleSwipePointerMove(PointerMoveEvent event) {
    if (event.pointer != _activeSwipePointer) return;
    _swipeLatestPosition = event.position;
  }

  void _handleSwipePointerUp(PointerUpEvent event) {
    if (event.pointer != _activeSwipePointer ||
        _swipeStartPosition == null ||
        _swipeStartedAt == null) {
      if (event.pointer == _activeSwipePointer) {
        _clearSwipeTracking();
      }
      return;
    }

    final endPosition = _swipeLatestPosition ?? event.position;
    final delta = endPosition - _swipeStartPosition!;
    final elapsed = DateTime.now().difference(_swipeStartedAt!);
    _clearSwipeTracking();

    if (elapsed > _calendarSwipeMaxDuration) return;
    if (delta.dx.abs() < _calendarSwipeDistanceThreshold) return;
    if (delta.dx.abs() < delta.dy.abs() * _calendarSwipeDirectionBias) return;

    final direction = delta.dx < 0 ? 1 : -1;
    _triggerSwipeNavigation(direction);
  }

  void _handleSwipeDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < _calendarSwipeVelocityThreshold) return;
    final direction = velocity < 0 ? 1 : -1;
    _triggerSwipeNavigation(direction);
  }

  void _handleSwipePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activeSwipePointer) return;
    _clearSwipeTracking();
  }

  void _clearSwipeTracking() {
    _activeSwipePointer = null;
    _swipeStartPosition = null;
    _swipeLatestPosition = null;
    _swipeStartedAt = null;
  }

  void _triggerSwipeNavigation(int direction) {
    if (_swipeNavigationConsumed) return;
    _swipeNavigationConsumed = true;
    widget.onAnchorDateChanged(
      _stepCalendarAnchor(
        widget.anchorDate,
        widget.subview,
        direction: direction,
      ),
    );
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}

class _CalendarSurfaceDelegate extends SliverPersistentHeaderDelegate {
  const _CalendarSurfaceDelegate({
    required this.extent,
    required this.child,
  });

  final double extent;
  final Widget child;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _CalendarSurfaceDelegate oldDelegate) {
    return extent != oldDelegate.extent || child != oldDelegate.child;
  }
}

class _CalendarToolbar extends StatelessWidget {
  const _CalendarToolbar({
    required this.subview,
    required this.anchorDate,
    required this.onAnchorDateChanged,
    required this.onSubviewChanged,
  });

  final BoardCalendarSubview subview;
  final DateTime anchorDate;
  final ValueChanged<DateTime> onAnchorDateChanged;
  final ValueChanged<BoardCalendarSubview> onSubviewChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Previous',
                  onPressed: () => onAnchorDateChanged(
                    _stepCalendarAnchor(anchorDate, subview, direction: -1),
                  ),
                  icon: const Icon(Icons.chevron_left),
                ),
                TextButton(
                  onPressed: () => onAnchorDateChanged(
                    DateTime(today.year, today.month, today.day),
                  ),
                  child: const Text('Today'),
                ),
                IconButton(
                  tooltip: 'Next',
                  onPressed: () => onAnchorDateChanged(
                    _stepCalendarAnchor(anchorDate, subview, direction: 1),
                  ),
                  icon: const Icon(Icons.chevron_right),
                ),
                Text(
                  _rangeTitle(anchorDate, subview),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in BoardCalendarSubview.values)
                  ChoiceChip(
                    label: Text(_subviewLabel(option)),
                    selected: option == subview,
                    onSelected: option == subview
                        ? null
                        : (_) => onSubviewChanged(option),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _subviewLabel(BoardCalendarSubview view) {
    return switch (view) {
      BoardCalendarSubview.month => 'Month',
      BoardCalendarSubview.week => 'Week',
      BoardCalendarSubview.day => 'Day',
    };
  }

  static String _rangeTitle(DateTime date, BoardCalendarSubview subview) {
    if (subview == BoardCalendarSubview.month) {
      return '${_monthName(date.month)} ${date.year}';
    }
    if (subview == BoardCalendarSubview.day) {
      return '${_monthName(date.month)} ${date.day}, ${date.year}';
    }
    final weekStart = _startOfWeek(date);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final startLabel = '${_monthNameShort(weekStart.month)} ${weekStart.day}';
    final endLabel = weekEnd.year == weekStart.year
        ? '${_monthNameShort(weekEnd.month)} ${weekEnd.day}, ${weekEnd.year}'
        : '${_monthNameShort(weekEnd.month)} ${weekEnd.day}, ${weekEnd.year}';
    return '$startLabel - $endLabel';
  }
}

class _MonthCalendarView extends StatelessWidget {
  const _MonthCalendarView({
    required this.anchorDate,
    required this.calendarSnapshot,
    required this.accentColorValuesByItemKey,
    required this.multiBoardScope,
    required this.focusedItemId,
    required this.selectedItemIds,
    required this.canModifyItemsByBoardId,
    required this.onSelectItem,
    required this.onOpenItemDetails,
    required this.onMoveDueDate,
  });

  final DateTime anchorDate;
  final BoardCalendarSnapshot calendarSnapshot;
  final Map<String, int> accentColorValuesByItemKey;
  final bool multiBoardScope;
  final String? focusedItemId;
  final Set<String> selectedItemIds;
  final Map<String, bool> canModifyItemsByBoardId;
  final ValueChanged<WorkItem> onSelectItem;
  final ValueChanged<WorkItem> onOpenItemDetails;
  final Future<void> Function(WorkItem item, DateTime date) onMoveDueDate;

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(anchorDate.year, anchorDate.month);
    final monthStart = _startOfWeek(firstOfMonth);
    final gridDays = List<DateTime>.generate(
      42,
      (index) => monthStart.add(Duration(days: index)),
      growable: false,
    );
    final placementsByDate = _groupByDate(calendarSnapshot.placements);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              for (final label in _weekdayShortLabels)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(label),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cellHeight =
                  ((constraints.maxHeight - (5 * 6)) / 6).clamp(52.0, 140.0);
              final cellWidth =
                  ((constraints.maxWidth - (6 * 6)) / 7).clamp(40.0, 180.0);
              final childAspectRatio = cellWidth / cellHeight;

              return GridView.builder(
                key: const ValueKey('calendar-month-grid'),
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: childAspectRatio,
                ),
                itemCount: gridDays.length,
                itemBuilder: (context, index) {
                  final day = gridDays[index];
                  final items = placementsByDate[_dateOnly(day)] ?? const [];
                  return _CalendarDayCell(
                    date: day,
                    isCurrentMonth: day.month == anchorDate.month,
                    placements: items,
                    accentColorValuesByItemKey: accentColorValuesByItemKey,
                    multiBoardScope: multiBoardScope,
                    focusedItemId: focusedItemId,
                    selectedItemIds: selectedItemIds,
                    canModifyItemsByBoardId: canModifyItemsByBoardId,
                    onSelectItem: onSelectItem,
                    onOpenItemDetails: onOpenItemDetails,
                    onMoveDueDate: onMoveDueDate,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WeekCalendarView extends StatelessWidget {
  const _WeekCalendarView({
    required this.anchorDate,
    required this.calendarSnapshot,
    required this.accentColorValuesByItemKey,
    required this.multiBoardScope,
    required this.focusedItemId,
    required this.selectedItemIds,
    required this.canModifyItemsByBoardId,
    required this.onSelectItem,
    required this.onOpenItemDetails,
    required this.onMoveDueDate,
  });

  final DateTime anchorDate;
  final BoardCalendarSnapshot calendarSnapshot;
  final Map<String, int> accentColorValuesByItemKey;
  final bool multiBoardScope;
  final String? focusedItemId;
  final Set<String> selectedItemIds;
  final Map<String, bool> canModifyItemsByBoardId;
  final ValueChanged<WorkItem> onSelectItem;
  final ValueChanged<WorkItem> onOpenItemDetails;
  final Future<void> Function(WorkItem item, DateTime date) onMoveDueDate;

  @override
  Widget build(BuildContext context) {
    final weekStart = _startOfWeek(anchorDate);
    final placementsByDate = _groupByDate(calendarSnapshot.placements);
    return ListView.separated(
      key: const ValueKey('calendar-week-scroll'),
      padding: EdgeInsets.zero,
      scrollDirection: Axis.horizontal,
      itemCount: 7,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (context, index) {
        final day = weekStart.add(Duration(days: index));
        return SizedBox(
          width: 250,
          child: _CalendarDayAgenda(
            date: day,
            placements: placementsByDate[_dateOnly(day)] ?? const [],
            accentColorValuesByItemKey: accentColorValuesByItemKey,
            multiBoardScope: multiBoardScope,
            focusedItemId: focusedItemId,
            selectedItemIds: selectedItemIds,
            canModifyItemsByBoardId: canModifyItemsByBoardId,
            onSelectItem: onSelectItem,
            onOpenItemDetails: onOpenItemDetails,
            onMoveDueDate: onMoveDueDate,
          ),
        );
      },
    );
  }
}

class _DayCalendarView extends StatelessWidget {
  const _DayCalendarView({
    required this.selectedDate,
    required this.calendarSnapshot,
    required this.accentColorValuesByItemKey,
    required this.multiBoardScope,
    required this.focusedItemId,
    required this.selectedItemIds,
    required this.canModifyItemsByBoardId,
    required this.onSelectItem,
    required this.onOpenItemDetails,
    required this.onMoveDueDate,
  });

  final DateTime selectedDate;
  final BoardCalendarSnapshot calendarSnapshot;
  final Map<String, int> accentColorValuesByItemKey;
  final bool multiBoardScope;
  final String? focusedItemId;
  final Set<String> selectedItemIds;
  final Map<String, bool> canModifyItemsByBoardId;
  final ValueChanged<WorkItem> onSelectItem;
  final ValueChanged<WorkItem> onOpenItemDetails;
  final Future<void> Function(WorkItem item, DateTime date) onMoveDueDate;

  @override
  Widget build(BuildContext context) {
    final placements = calendarSnapshot.placements
        .where((placement) => _sameDate(placement.date, selectedDate))
        .toList(growable: false);
    final grouped = <BoardCalendarMarkerKind, List<BoardCalendarPlacement>>{
      for (final kind in BoardCalendarMarkerKind.values)
        kind: <BoardCalendarPlacement>[],
    };
    for (final placement in placements) {
      grouped
          .putIfAbsent(placement.kind, () => <BoardCalendarPlacement>[])
          .add(placement);
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _CalendarDayAgenda(
          date: selectedDate,
          placements: placements,
          accentColorValuesByItemKey: accentColorValuesByItemKey,
          multiBoardScope: multiBoardScope,
          focusedItemId: focusedItemId,
          selectedItemIds: selectedItemIds,
          canModifyItemsByBoardId: canModifyItemsByBoardId,
          onSelectItem: onSelectItem,
          onOpenItemDetails: onOpenItemDetails,
          onMoveDueDate: onMoveDueDate,
          grouped: grouped,
          showHeader: false,
        ),
      ],
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.date,
    required this.isCurrentMonth,
    required this.placements,
    required this.accentColorValuesByItemKey,
    required this.multiBoardScope,
    required this.focusedItemId,
    required this.selectedItemIds,
    required this.canModifyItemsByBoardId,
    required this.onSelectItem,
    required this.onOpenItemDetails,
    required this.onMoveDueDate,
  });

  final DateTime date;
  final bool isCurrentMonth;
  final List<BoardCalendarPlacement> placements;
  final Map<String, int> accentColorValuesByItemKey;
  final bool multiBoardScope;
  final String? focusedItemId;
  final Set<String> selectedItemIds;
  final Map<String, bool> canModifyItemsByBoardId;
  final ValueChanged<WorkItem> onSelectItem;
  final ValueChanged<WorkItem> onOpenItemDetails;
  final Future<void> Function(WorkItem item, DateTime date) onMoveDueDate;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final isToday = _sameDate(today, date);
    return DragTarget<WorkItem>(
      key: ValueKey('calendar-agenda-day-${date.toIso8601String()}'),
      onWillAcceptWithDetails: (details) =>
          canModifyItemsByBoardId[details.data.boardId] == true,
      onAcceptWithDetails: (details) => onMoveDueDate(details.data, date),
      builder: (context, candidateData, _) {
        final theme = Theme.of(context);
        final highlight = candidateData.isNotEmpty;
        return InkWell(
          key: ValueKey('calendar-day-${date.toIso8601String()}'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showDayAgendaSheet(context),
          child: Container(
            decoration: BoxDecoration(
              color: highlight
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                  : theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isToday
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${date.day}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: isCurrentMonth
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                const Spacer(),
                if (placements.isNotEmpty)
                  SizedBox(
                    height: 12,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final maxVisibleDots = _maxMonthDots(
                          placements.length,
                          constraints.maxWidth,
                        );
                        final hiddenCount = placements.length - maxVisibleDots;
                        final visiblePlacements = placements
                            .take(maxVisibleDots)
                            .toList(growable: false);

                        return Row(
                          key: ValueKey(
                            'calendar-day-dots-${date.toIso8601String()}',
                          ),
                          children: [
                            for (final placement in visiblePlacements)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color:
                                        _markerColor(context, placement.kind),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            if (hiddenCount > 0)
                              Flexible(
                                child: Text(
                                  '+$hiddenCount',
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDayAgendaSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.94,
        builder: (context, scrollController) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              key: const ValueKey('calendar-day-agenda-sheet-scroll'),
              controller: scrollController,
              child: _CalendarDayAgenda(
                date: date,
                placements: placements,
                accentColorValuesByItemKey: accentColorValuesByItemKey,
                multiBoardScope: multiBoardScope,
                focusedItemId: focusedItemId,
                selectedItemIds: selectedItemIds,
                canModifyItemsByBoardId: canModifyItemsByBoardId,
                onSelectItem: onSelectItem,
                onOpenItemDetails: onOpenItemDetails,
                onMoveDueDate: onMoveDueDate,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

int _maxMonthDots(int totalPlacements, double availableWidth) {
  if (totalPlacements <= 0 || availableWidth <= 0) return 0;

  final slotWidth = 12.0;
  int visibleDots =
      (availableWidth / slotWidth).floor().clamp(1, totalPlacements);

  while (visibleDots > 0) {
    final hiddenCount = totalPlacements - visibleDots;
    final countWidth = hiddenCount > 0 ? (hiddenCount > 9 ? 28.0 : 22.0) : 0.0;
    final requiredWidth = (visibleDots * slotWidth) + countWidth;
    if (requiredWidth <= availableWidth) break;
    visibleDots -= 1;
  }

  return visibleDots.clamp(0, totalPlacements);
}

class _CalendarDayAgenda extends StatelessWidget {
  const _CalendarDayAgenda({
    required this.date,
    required this.placements,
    required this.accentColorValuesByItemKey,
    required this.multiBoardScope,
    required this.focusedItemId,
    required this.selectedItemIds,
    required this.canModifyItemsByBoardId,
    required this.onSelectItem,
    required this.onOpenItemDetails,
    required this.onMoveDueDate,
    this.grouped,
    this.showHeader = true,
  });

  final DateTime date;
  final List<BoardCalendarPlacement> placements;
  final Map<String, int> accentColorValuesByItemKey;
  final bool multiBoardScope;
  final String? focusedItemId;
  final Set<String> selectedItemIds;
  final Map<String, bool> canModifyItemsByBoardId;
  final ValueChanged<WorkItem> onSelectItem;
  final ValueChanged<WorkItem> onOpenItemDetails;
  final Future<void> Function(WorkItem item, DateTime date) onMoveDueDate;
  final Map<BoardCalendarMarkerKind, List<BoardCalendarPlacement>>? grouped;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final groupedPlacements = grouped ??
        <BoardCalendarMarkerKind, List<BoardCalendarPlacement>>{
          for (final kind in BoardCalendarMarkerKind.values)
            kind: placements
                .where((placement) => placement.kind == kind)
                .toList(growable: false),
        };

    return DragTarget<WorkItem>(
      onWillAcceptWithDetails: (details) =>
          canModifyItemsByBoardId[details.data.boardId] == true,
      onAcceptWithDetails: (details) => onMoveDueDate(details.data, date),
      builder: (context, candidateData, _) {
        final theme = Theme.of(context);
        final highlight = candidateData.isNotEmpty;
        return Card(
          margin: EdgeInsets.zero,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: highlight
                  ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                  : null,
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showHeader) ...[
                  Text(
                    '${_weekdayLabel(date.weekday)}, ${_monthNameShort(date.month)} ${date.day}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                for (final kind in BoardCalendarMarkerKind.values)
                  if ((groupedPlacements[kind] ?? const []).isNotEmpty) ...[
                    Text(
                      _markerLabel(kind),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: _markerColor(context, kind),
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final placement in groupedPlacements[kind]!)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CalendarPlacementCard(
                          placement: placement,
                          accentColorValue: accentColorValuesByItemKey[
                              '${placement.item.boardId}::${placement.item.itemId}'],
                          multiBoardScope: multiBoardScope,
                          focused: focusedItemId == placement.item.itemId,
                          selected:
                              selectedItemIds.contains(placement.item.itemId),
                          canDrag:
                              canModifyItemsByBoardId[placement.item.boardId] ==
                                  true,
                          onSelect: () => onSelectItem(placement.item),
                          onOpenDetails: () =>
                              onOpenItemDetails(placement.item),
                          compact: false,
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                if (placements.isEmpty)
                  Text(
                    'Nothing scheduled for this day.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CalendarUnscheduledTray extends StatelessWidget {
  const _CalendarUnscheduledTray({
    required this.height,
    required this.isOpen,
    required this.itemCount,
    required this.unscheduledItems,
    required this.accentColorValuesByItemKey,
    required this.multiBoardScope,
    required this.focusedItemId,
    required this.selectedItemIds,
    required this.canModifyItemsByBoardId,
    required this.onToggle,
    required this.onSelectItem,
    required this.onOpenItemDetails,
    required this.onMoveDueDate,
    required this.onStartDrag,
  });

  final double height;
  final bool isOpen;
  final int itemCount;
  final List<BoardCalendarUnscheduledItem> unscheduledItems;
  final Map<String, int> accentColorValuesByItemKey;
  final bool multiBoardScope;
  final String? focusedItemId;
  final Set<String> selectedItemIds;
  final Map<String, bool> canModifyItemsByBoardId;
  final VoidCallback onToggle;
  final ValueChanged<WorkItem> onSelectItem;
  final ValueChanged<WorkItem> onOpenItemDetails;
  final Future<void> Function(WorkItem item, DateTime date) onMoveDueDate;
  final VoidCallback onStartDrag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      key: const ValueKey('calendar-unscheduled-tray'),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            InkWell(
              key: const ValueKey('calendar-unscheduled-tray-toggle'),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(22)),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.outlineVariant,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          Text(
                            'Unscheduled ($itemCount)',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isOpen
                                ? 'Scroll the list or drag an item onto the calendar.'
                                : 'Tap to browse or drag items onto a date.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      isOpen ? Icons.expand_more : Icons.expand_less,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (isOpen)
              Expanded(
                child: ListView.separated(
                  key: const ValueKey('calendar-unscheduled-tray-list'),
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: unscheduledItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = unscheduledItems[index];
                    return _UnscheduledItemCard(
                      entry: entry,
                      accentColorValue: accentColorValuesByItemKey[
                          '${entry.item.boardId}::${entry.item.itemId}'],
                      multiBoardScope: multiBoardScope,
                      focused: focusedItemId == entry.item.itemId,
                      selected: selectedItemIds.contains(entry.item.itemId),
                      canDrag:
                          canModifyItemsByBoardId[entry.item.boardId] == true,
                      onSelect: () => onSelectItem(entry.item),
                      onOpenDetails: () => onOpenItemDetails(entry.item),
                      onStartDrag: onStartDrag,
                      onPickDate: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime(
                            now.year,
                            now.month,
                            now.day,
                          ),
                          firstDate: DateTime(now.year - 5),
                          lastDate: DateTime(now.year + 10),
                        );
                        if (picked == null) return;
                        await onMoveDueDate(
                          entry.item,
                          DateTime(picked.year, picked.month, picked.day),
                        );
                      },
                    );
                  },
                ),
              )
            else
              const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _CalendarPlacementCard extends StatelessWidget {
  const _CalendarPlacementCard({
    required this.placement,
    required this.accentColorValue,
    required this.multiBoardScope,
    required this.focused,
    required this.selected,
    required this.canDrag,
    required this.onSelect,
    required this.onOpenDetails,
    this.compact = false,
  });

  final BoardCalendarPlacement placement;
  final int? accentColorValue;
  final bool multiBoardScope;
  final bool focused;
  final bool selected;
  final bool canDrag;
  final VoidCallback onSelect;
  final VoidCallback onOpenDetails;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor =
        accentColorValue == null ? null : Color(accentColorValue!);
    final card = Container(
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.secondaryContainer
            : (focused
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surface),
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 6 : 8,
      ),
      child: Row(
        children: [
          Container(
            key: ValueKey(
              'calendar-placement-accent-${placement.item.boardId}-${placement.item.itemId}',
            ),
            width: 4,
            height: compact ? 30 : 38,
            decoration: BoxDecoration(
              color: accentColor ?? _markerColor(context, placement.kind),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  placement.item.title,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: compact
                      ? theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        )
                      : theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                ),
                const SizedBox(height: 2),
                Text(
                  multiBoardScope
                      ? '${_markerLabel(placement.kind)} • ${placement.boardName}'
                      : _markerLabel(placement.kind),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _markerColor(context, placement.kind),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final interactive = InkWell(
      borderRadius: BorderRadius.circular(compact ? 10 : 12),
      onTap: onSelect,
      onDoubleTap: () {
        onSelect();
        onOpenDetails();
      },
      child: card,
    );

    if (!canDrag) return interactive;
    return LongPressDraggable<WorkItem>(
      data: placement.item,
      feedback: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: card,
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: interactive),
      child: interactive,
    );
  }
}

class _UnscheduledItemCard extends StatelessWidget {
  const _UnscheduledItemCard({
    required this.entry,
    required this.accentColorValue,
    required this.multiBoardScope,
    required this.focused,
    required this.selected,
    required this.canDrag,
    required this.onSelect,
    required this.onOpenDetails,
    required this.onPickDate,
    required this.onStartDrag,
  });

  final BoardCalendarUnscheduledItem entry;
  final int? accentColorValue;
  final bool multiBoardScope;
  final bool focused;
  final bool selected;
  final bool canDrag;
  final VoidCallback onSelect;
  final VoidCallback onOpenDetails;
  final Future<void> Function() onPickDate;
  final VoidCallback onStartDrag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = accentColorValue == null
        ? theme.colorScheme.outlineVariant
        : Color(accentColorValue!);
    final child = Container(
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.secondaryContainer
            : (focused
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Container(
            key: ValueKey(
              'calendar-unscheduled-accent-${entry.item.boardId}-${entry.item.itemId}',
            ),
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.event_busy_outlined,
            size: 18,
            color: accentColorValue == null ? null : accentColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (multiBoardScope)
                  Text(
                    entry.boardName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () async {
              onSelect();
              await onPickDate();
            },
            child: const Text('Pick date'),
          ),
        ],
      ),
    );
    final interactive = InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onSelect,
      onDoubleTap: () {
        onSelect();
        onOpenDetails();
      },
      child: child,
    );
    if (!canDrag) return interactive;
    return LongPressDraggable<WorkItem>(
      data: entry.item,
      onDragStarted: onStartDrag,
      feedback: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: child,
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: interactive),
      child: interactive,
    );
  }
}

Map<DateTime, List<BoardCalendarPlacement>> _groupByDate(
  List<BoardCalendarPlacement> placements,
) {
  final grouped = <DateTime, List<BoardCalendarPlacement>>{};
  for (final placement in placements) {
    grouped
        .putIfAbsent(
            _dateOnly(placement.date), () => <BoardCalendarPlacement>[])
        .add(placement);
  }
  return grouped;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _stepCalendarAnchor(
  DateTime anchorDate,
  BoardCalendarSubview subview, {
  required int direction,
}) {
  return switch (subview) {
    BoardCalendarSubview.month =>
      DateTime(anchorDate.year, anchorDate.month + direction, anchorDate.day),
    BoardCalendarSubview.week => anchorDate.add(Duration(days: 7 * direction)),
    BoardCalendarSubview.day => anchorDate.add(Duration(days: direction)),
  };
}

DateTime _startOfWeek(DateTime value) {
  final normalized = _dateOnly(value);
  return normalized.subtract(Duration(days: normalized.weekday - 1));
}

bool _sameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _markerLabel(BoardCalendarMarkerKind kind) {
  return switch (kind) {
    BoardCalendarMarkerKind.start => 'Start',
    BoardCalendarMarkerKind.targetEnd => 'Target',
    BoardCalendarMarkerKind.due => 'Due',
  };
}

Color _markerColor(BuildContext context, BoardCalendarMarkerKind kind) {
  final scheme = Theme.of(context).colorScheme;
  return switch (kind) {
    BoardCalendarMarkerKind.start => scheme.tertiary,
    BoardCalendarMarkerKind.targetEnd => scheme.secondary,
    BoardCalendarMarkerKind.due => scheme.primary,
  };
}

String _monthName(int month) {
  const names = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return names[month - 1];
}

String _monthNameShort(int month) {
  return _monthName(month).substring(0, 3);
}

String _weekdayLabel(int weekday) {
  return const <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][weekday - 1];
}

const List<String> _weekdayShortLabels = <String>[
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];
