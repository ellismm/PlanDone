import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_navigation_shell.dart';
import '../../../app_routes.dart';
import '../../../core/help/app_help.dart';
import '../../../core/help/app_help_widgets.dart';
import '../domain/models/board_insights.dart';
import '../domain/models/work_item_type.dart';
import 'board_controller.dart';
import 'board_view_ui.dart';

const _insightsHeaderHelpSpec = AppHelpTargetSpec(
  id: AppHelpTargetIds.insightsHeader,
  title: 'Insights header',
  description:
      'The header tells you which board and time range you are reading right now.',
  whenToUse:
      'Use it when you want to switch between recent and longer-range signals before reading the numbers.',
  whatHappens:
      'Changing the range updates the cards below so you can compare short-term execution and longer patterns.',
  icon: Icons.query_stats_outlined,
  tourId: AppHelpTourId.insights,
);

const _insightsAccomplishedHelpSpec = AppHelpTargetSpec(
  id: AppHelpTargetIds.insightsAccomplished,
  title: 'Accomplished',
  description:
      'This section shows what actually got finished in the selected time window.',
  whenToUse:
      'Use it when you want a grounded read on output, by both item type and total impact.',
  whatHappens:
      'It shows completed counts, impact score, and change versus the previous window when that comparison makes sense.',
  icon: Icons.task_alt_outlined,
  tourId: AppHelpTourId.insights,
);

const _insightsMomentumHelpSpec = AppHelpTargetSpec(
  id: AppHelpTargetIds.insightsMomentum,
  title: 'Momentum',
  description:
      'Momentum shows whether work is continuing steadily instead of stalling out.',
  whenToUse:
      'Use it when you want to see whether you are sustaining progress over time, not just finishing a single burst of work.',
  whatHappens:
      'It highlights streaks and trend direction so you can spot when momentum is building, flattening, or slipping.',
  icon: Icons.local_fire_department_outlined,
  tourId: AppHelpTourId.insights,
);

const _insightsBoardHealthHelpSpec = AppHelpTargetSpec(
  id: AppHelpTargetIds.insightsBoardHealth,
  title: 'Board health',
  description:
      'Board health looks for friction in the system, like overdue, blocked, or stale work.',
  whenToUse:
      'Use it when the board feels heavy and you want to understand whether the problem is lateness, blockage, or stale active items.',
  whatHappens:
      'It summarizes the load that may be slowing the board down so you can clean up the right kind of bottleneck.',
  icon: Icons.health_and_safety_outlined,
  tourId: AppHelpTourId.insights,
);

const _insightsAttentionHelpSpec = AppHelpTargetSpec(
  id: AppHelpTargetIds.insightsAttention,
  title: 'Attention signals',
  description:
      'These are early warning signs that work may be slipping before it becomes a bigger problem.',
  whenToUse:
      'Use them when you want to spot churn, slipping due dates, or capture debt that needs a quick cleanup.',
  whatHappens:
      'The section surfaces reopened work, slipped due dates, and inbox buildup so you can intervene earlier.',
  icon: Icons.notification_important_outlined,
  tourId: AppHelpTourId.insights,
);

class BoardInsightsPage extends ConsumerWidget {
  const BoardInsightsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(boardStreamProvider);
    final insightsAsync = ref.watch(boardInsightsProvider);
    final selectedRange = ref.watch(selectedBoardInsightsRangeProvider);
    final planningView = ref.watch(boardPlanningViewProvider);

    return AppPrimaryScaffold(
      activeRoute: AppRoutes.insights,
      title: 'Insights',
      helpSurface: AppHelpSurfaceId.insights,
      workspaceIcon: boardPlanningViewIcon(planningView),
      workspaceSelectedIcon: boardPlanningViewSelectedIcon(planningView),
      body: snapshotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Unable to load board: $error')),
        data: (snapshot) => insightsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              Center(child: Text('Unable to load insights: $error')),
          data: (insights) => _InsightsContent(
            boardName: snapshot.board.name,
            selectedRange: selectedRange,
            insights: insights,
          ),
        ),
      ),
    );
  }
}

class _InsightsContent extends ConsumerWidget {
  const _InsightsContent({
    required this.boardName,
    required this.selectedRange,
    required this.insights,
  });

  final String boardName;
  final BoardInsightsRange selectedRange;
  final BoardInsightsSnapshot insights;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        AppHelpTarget(
          spec: _insightsHeaderHelpSpec,
          borderRadius: BorderRadius.circular(28),
          child: _InsightsHero(
            boardName: boardName,
            selectedRange: selectedRange,
            insights: insights,
            onRangeChanged: (range) {
              ref.read(selectedBoardInsightsRangeProvider.notifier).state =
                  range;
            },
          ),
        ),
        const SizedBox(height: 14),
        _FocusPromptCard(insights: insights),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Today & next',
          subtitle:
              'A quick read on what is pressing, what is ready, and how much is still open.',
          tone: _toneForMood(insights.mood),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricTile(
                    label: 'Due today',
                    value: '${insights.dueTodayOpenCount}',
                    icon: Icons.today_outlined,
                    tone: _MetricTone.warm,
                    footer: insights.dueSoonOpenCount == 0
                        ? 'No dated pressure this week'
                        : '${insights.dueSoonOpenCount} due in 7 days',
                  ),
                  _MetricTile(
                    label: 'Open actions',
                    value: '${insights.openActionCount}',
                    icon: Icons.bolt_outlined,
                    tone: _MetricTone.fresh,
                    footer: insights.undatedOpenActionCount == 0
                        ? 'All actions have dates'
                        : '${insights.undatedOpenActionCount} without due dates',
                  ),
                  _MetricTile(
                    label: 'Active now',
                    value: '${insights.activeExecutionCount}',
                    icon: Icons.track_changes_outlined,
                    tone: _MetricTone.cool,
                    footer:
                        '${insights.readyQueueCount} waiting in ready/planning',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _BalanceBar(
                label: 'Action share of open work',
                value: insights.actionShareOfOpen,
                leadingLabel: '${insights.openActionCount} actions',
                trailingLabel: '${insights.openTotalCount} open total',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppHelpTarget(
          spec: _insightsAccomplishedHelpSpec,
          borderRadius: BorderRadius.circular(16),
          child: _SectionCard(
            title: 'Accomplished',
            subtitle:
                'What got finished in ${selectedRange.rangeLabel.toLowerCase()}.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (insights.completedTotal == 0)
                  Text(
                    'No completed work in this window yet. The board is still tracking current work, and the next completion will start this story.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else ...[
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final type in WorkItemType.values)
                        _MetricTile(
                          label: _typeLabel(type),
                          value: '${insights.completedByType[type] ?? 0}',
                          icon: _typeIcon(type),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MetricTile(
                      label: 'Completed total',
                      value: '${insights.completedTotal}',
                      icon: Icons.task_alt_outlined,
                      tone: _MetricTone.fresh,
                      footer: _deltaLabel(
                        insights.completedDelta,
                        noun: 'items',
                      ),
                    ),
                    _MetricTile(
                      label: 'Impact score',
                      value: '${insights.impactScore}',
                      icon: Icons.bolt_outlined,
                      tone: _MetricTone.warm,
                      footer: _deltaLabel(
                        insights.impactDelta,
                        noun: 'pts',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        AppHelpTarget(
          spec: _insightsMomentumHelpSpec,
          borderRadius: BorderRadius.circular(16),
          child: _SectionCard(
            title: 'Momentum',
            subtitle:
                'Progress signals that keep the board moving without turning it into a game.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MetricTile(
                      label: 'Current streak',
                      value: '${insights.currentStreak}',
                      icon: Icons.local_fire_department_outlined,
                      tone: _MetricTone.warm,
                      footer: insights.currentStreak == 1 ? 'day' : 'days',
                    ),
                    _MetricTile(
                      label: 'Best streak',
                      value: '${insights.bestStreak}',
                      icon: Icons.insights_outlined,
                      tone: _MetricTone.cool,
                      footer: insights.bestStreak == 1 ? 'day' : 'days',
                    ),
                    _MetricTile(
                      label: 'Active days',
                      value: '${insights.completionActiveDayCount}',
                      icon: Icons.calendar_month_outlined,
                      tone: _MetricTone.fresh,
                      footer:
                          '${_formatDecimal(insights.averageCompletedPerActiveDay)} done / active day',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Completion trend · ${insights.trendGranularity.label}',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                _TrendStrip(insights: insights),
                const SizedBox(height: 8),
                Text(
                  insights.range == BoardInsightsRange.allTime
                      ? 'Monthly trend over the last 12 months.'
                      : 'Compared with the immediately previous ${selectedRange.rangeLabel.toLowerCase()} window.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Work shape',
          subtitle:
              'How the board is weighted right now, so the next cleanup pass has a direction.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricTile(
                    label: 'Open total',
                    value: '${insights.openTotalCount}',
                    icon: Icons.inventory_2_outlined,
                    tone: _MetricTone.neutral,
                    footer: '${insights.openTaskCount} tasks still open',
                  ),
                  _MetricTile(
                    label: 'New in range',
                    value: '${insights.recentlyCreatedCount}',
                    icon: Icons.add_circle_outline,
                    tone: _MetricTone.cool,
                    footer: 'Fresh work added',
                  ),
                  _MetricTile(
                    label: 'Pressure points',
                    value: '${insights.pressureCount}',
                    icon: Icons.speed_outlined,
                    tone: insights.pressureCount == 0
                        ? _MetricTone.fresh
                        : _MetricTone.warm,
                    footer: 'Overdue + due today + blocked + stale',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _InsightCallout(
                icon: Icons.auto_awesome_outlined,
                title: insights.mood.label,
                message: _moodMessage(insights),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppHelpTarget(
          spec: _insightsBoardHealthHelpSpec,
          borderRadius: BorderRadius.circular(16),
          child: _SectionCard(
            title: 'Board health',
            subtitle:
                'Is the work moving cleanly or piling up in the wrong places?',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricTile(
                  label: 'On-time completion rate',
                  value: insights.onTimeCompletionRate == null
                      ? '—'
                      : '${(insights.onTimeCompletionRate! * 100).round()}%',
                  icon: Icons.schedule_outlined,
                  tone: _MetricTone.cool,
                  footer: insights.onTimeCompletionRate == null
                      ? 'No due-date completions yet'
                      : '${insights.onTimeCompletionCount}/${insights.dueTrackedCompletionCount} on time',
                ),
                _MetricTile(
                  label: 'Overdue open',
                  value: '${insights.overdueOpenCount}',
                  icon: Icons.warning_amber_outlined,
                  tone: insights.overdueOpenCount == 0
                      ? _MetricTone.fresh
                      : _MetricTone.warm,
                ),
                _MetricTile(
                  label: 'Blocked load',
                  value: '${insights.blockedLoadCount}',
                  icon: Icons.block_outlined,
                  tone: insights.blockedLoadCount == 0
                      ? _MetricTone.fresh
                      : _MetricTone.danger,
                ),
                _MetricTile(
                  label: 'Stale active',
                  value: '${insights.staleActiveCount}',
                  icon: Icons.timelapse_outlined,
                  tone: insights.staleActiveCount == 0
                      ? _MetricTone.fresh
                      : _MetricTone.warm,
                  footer: 'No update in 7+ days',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        AppHelpTarget(
          spec: _insightsAttentionHelpSpec,
          borderRadius: BorderRadius.circular(16),
          child: _SectionCard(
            title: 'Attention',
            subtitle:
                'Secondary signals that help spot friction before it becomes drift.',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricTile(
                  label: 'Reopened in range',
                  value: '${insights.reopenedCount}',
                  icon: Icons.restart_alt_outlined,
                  tone: _MetricTone.neutral,
                ),
                _MetricTile(
                  label: 'Slipped due',
                  value: '${insights.slippedDueCount}',
                  icon: Icons.event_busy_outlined,
                  tone: insights.slippedDueCount == 0
                      ? _MetricTone.fresh
                      : _MetricTone.warm,
                ),
                _MetricTile(
                  label: 'Inbox pending',
                  value: '${insights.inboxPendingCount}',
                  icon: Icons.inbox_outlined,
                  tone: insights.inboxPendingCount == 0
                      ? _MetricTone.fresh
                      : _MetricTone.cool,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String? _deltaLabel(BoardInsightsDelta? delta, {required String noun}) {
    if (delta == null) return null;
    if (delta.difference == 0) return 'Flat vs previous';
    final prefix = delta.difference > 0 ? '+' : '';
    return '$prefix${delta.difference} $noun vs previous';
  }

  String _typeLabel(WorkItemType type) {
    return switch (type) {
      WorkItemType.goal => 'Goals',
      WorkItemType.project => 'Projects',
      WorkItemType.task => 'Tasks',
      WorkItemType.action => 'Actions',
    };
  }

  IconData _typeIcon(WorkItemType type) {
    return switch (type) {
      WorkItemType.goal => Icons.flag_outlined,
      WorkItemType.project => Icons.folder_outlined,
      WorkItemType.task => Icons.checklist_outlined,
      WorkItemType.action => Icons.playlist_add_check_circle_outlined,
    };
  }

  _MetricTone _toneForMood(BoardInsightsMood mood) {
    return switch (mood) {
      BoardInsightsMood.clear => _MetricTone.fresh,
      BoardInsightsMood.moving => _MetricTone.cool,
      BoardInsightsMood.heavy => _MetricTone.warm,
      BoardInsightsMood.quiet => _MetricTone.neutral,
    };
  }

  String _moodMessage(BoardInsightsSnapshot insights) {
    return switch (insights.mood) {
      BoardInsightsMood.clear =>
        'The board has recent completions and low friction. Keep the day simple: pick the next small action.',
      BoardInsightsMood.moving =>
        'There is active work in motion. Protect momentum by finishing or clarifying one thing before adding more.',
      BoardInsightsMood.heavy =>
        'The board is carrying pressure. A short cleanup pass will probably help more than adding new work.',
      BoardInsightsMood.quiet =>
        'Not much is moving yet. That can be fine, but the next useful step is to capture or choose one concrete action.',
    };
  }

  String _formatDecimal(double value) {
    if (value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.tone = _MetricTone.neutral,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final _MetricTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _toneColor(theme, tone);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 28,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.tone = _MetricTone.neutral,
    this.footer,
  });

  final String label;
  final String value;
  final IconData icon;
  final _MetricTone tone;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _toneColor(theme, tone);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.16),
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.46),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.24)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (footer != null) ...[
                const SizedBox(height: 6),
                Text(
                  footer!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InsightsHero extends StatelessWidget {
  const _InsightsHero({
    required this.boardName,
    required this.selectedRange,
    required this.insights,
    required this.onRangeChanged,
  });

  final String boardName;
  final BoardInsightsRange selectedRange;
  final BoardInsightsSnapshot insights;
  final ValueChanged<BoardInsightsRange> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _toneColor(theme, _toneForMood(insights.mood));
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.22),
            theme.colorScheme.primaryContainer.withValues(alpha: 0.42),
            theme.colorScheme.surface,
          ],
        ),
        border: Border.all(
          color: accent.withValues(alpha: 0.22),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        boardName,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Board-neutral progress and execution health for ${selectedRange.rangeLabel.toLowerCase()}.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _MoodBadge(mood: insights.mood),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _HeroStat(
                  label: 'Completed',
                  value: '${insights.completedTotal}',
                  icon: Icons.task_alt_outlined,
                ),
                _HeroStat(
                  label: 'Open',
                  value: '${insights.openTotalCount}',
                  icon: Icons.inventory_2_outlined,
                ),
                _HeroStat(
                  label: 'Pressure',
                  value: '${insights.pressureCount}',
                  icon: Icons.speed_outlined,
                ),
              ],
            ),
            const SizedBox(height: 18),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<BoardInsightsRange>(
                showSelectedIcon: false,
                segments: [
                  for (final range in BoardInsightsRange.values)
                    ButtonSegment<BoardInsightsRange>(
                      value: range,
                      label: Text(range.shortLabel),
                    ),
                ],
                selected: {selectedRange},
                onSelectionChanged: (selection) {
                  onRangeChanged(selection.first);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusPromptCard extends StatelessWidget {
  const _FocusPromptCard({required this.insights});

  final BoardInsightsSnapshot insights;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _toneColor(theme, _toneForMood(insights.mood));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.16),
              ),
              child: Icon(Icons.psychology_alt_outlined, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Suggested next read',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    insights.focusPrompt,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 104,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MoodBadge extends StatelessWidget {
  const _MoodBadge({required this.mood});

  final BoardInsightsMood mood;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _toneColor(theme, _toneForMood(mood));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 9, color: accent),
            const SizedBox(width: 8),
            Text(
              mood.label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceBar extends StatelessWidget {
  const _BalanceBar({
    required this.label,
    required this.value,
    required this.leadingLabel,
    required this.trailingLabel,
  });

  final String label;
  final double value;
  final String leadingLabel;
  final String trailingLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clamped = value.clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: clamped,
            minHeight: 12,
            color: theme.colorScheme.primary,
            backgroundColor:
                theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.64,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              leadingLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              trailingLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InsightCallout extends StatelessWidget {
  const _InsightCallout({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _MetricTone {
  neutral,
  fresh,
  warm,
  cool,
  danger,
}

_MetricTone _toneForMood(BoardInsightsMood mood) {
  return switch (mood) {
    BoardInsightsMood.clear => _MetricTone.fresh,
    BoardInsightsMood.moving => _MetricTone.cool,
    BoardInsightsMood.heavy => _MetricTone.warm,
    BoardInsightsMood.quiet => _MetricTone.neutral,
  };
}

Color _toneColor(ThemeData theme, _MetricTone tone) {
  return switch (tone) {
    _MetricTone.neutral => theme.colorScheme.primary,
    _MetricTone.fresh => const Color(0xFF18885A),
    _MetricTone.warm => const Color(0xFFC06A1A),
    _MetricTone.cool => const Color(0xFF2F6FB2),
    _MetricTone.danger => theme.colorScheme.error,
  };
}

class _TrendStrip extends StatelessWidget {
  const _TrendStrip({required this.insights});

  final BoardInsightsSnapshot insights;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxCount = insights.completionTrend.fold<int>(
      0,
      (best, bucket) =>
          bucket.completedCount > best ? bucket.completedCount : best,
    );

    if (insights.completionTrend.isEmpty) {
      return Text(
        'No completion trend available yet.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return SizedBox(
      height: 90,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final bucket in insights.completionTrend)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Tooltip(
                  message: '${bucket.label}: ${bucket.completedCount}',
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: maxCount == 0
                            ? 6
                            : 6 + ((bucket.completedCount / maxCount) * 54),
                        decoration: BoxDecoration(
                          color: bucket.completedCount == 0
                              ? theme.colorScheme.surfaceContainerHighest
                              : theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        bucket.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
