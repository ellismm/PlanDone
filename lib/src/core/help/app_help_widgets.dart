import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/board/presentation/board_controller.dart';
import 'app_help.dart';
import 'app_help_controller.dart';

class AppHelpTarget extends ConsumerStatefulWidget {
  const AppHelpTarget({
    super.key,
    required this.spec,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.enabled = true,
  });

  final AppHelpTargetSpec spec;
  final Widget child;
  final BorderRadius borderRadius;
  final bool enabled;

  @override
  ConsumerState<AppHelpTarget> createState() => _AppHelpTargetState();
}

class _AppHelpTargetState extends ConsumerState<AppHelpTarget> {
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _targetKey = GlobalKey();
  Size? _lastSize;
  ProviderContainer? _container;
  String? _lastEnsuredTourToken;

  @override
  void initState() {
    super.initState();
    _scheduleSync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container ??= ProviderScope.containerOf(context, listen: false);
  }

  @override
  void didUpdateWidget(covariant AppHelpTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spec.id != widget.spec.id) {
      _scheduleUnregister(oldWidget.spec.id);
    }
    if (oldWidget.spec.id != widget.spec.id ||
        oldWidget.enabled != widget.enabled ||
        oldWidget.borderRadius != widget.borderRadius) {
      _scheduleSync();
    }
  }

  @override
  void dispose() {
    _scheduleUnregister(widget.spec.id);
    super.dispose();
  }

  void _scheduleSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncTarget());
  }

  void _scheduleUnregister(AppHelpTargetId targetId) {
    final container = _container;
    if (container == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        container
            .read(appHelpControllerProvider)
            .unregisterVisibleTarget(targetId);
      } on StateError {
        // The help overlay can outlive the test/provider container teardown.
      }
    });
  }

  void _syncTarget() {
    if (!mounted) return;
    if (!widget.enabled) {
      ref
          .read(appHelpControllerProvider)
          .unregisterVisibleTarget(widget.spec.id);
      return;
    }

    final context = _targetKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return;
    }
    final size = renderObject.size;
    if (size.isEmpty) {
      ref
          .read(appHelpControllerProvider)
          .unregisterVisibleTarget(widget.spec.id);
      return;
    }
    if (_lastSize == size) {
      return;
    }
    _lastSize = size;
    ref.read(appHelpControllerProvider).registerVisibleTarget(
          AppHelpVisibleTarget(
            spec: widget.spec,
            link: _layerLink,
            size: size,
            borderRadius: widget.borderRadius,
          ),
        );
  }

  void _scheduleEnsureVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetContext = _targetKey.currentContext;
      if (targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.2,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleSync();
    final helpModeEnabled = ref.watch(appHelpModeEnabledProvider);
    final activeTour =
        ref.watch(appHelpCurrentSurfaceTourProvider(widget.spec.id.surface));
    final currentStep = ref.watch(appHelpCurrentTourStepProvider);
    final isCurrentTourStep = currentStep?.targetId == widget.spec.id;
    final showInlineHelpOverlay =
        widget.enabled && (helpModeEnabled || isCurrentTourStep);
    final currentTourToken = activeTour == null || !isCurrentTourStep
        ? null
        : '${activeTour.tourId.name}:${activeTour.stepIndex}';

    if (currentTourToken != null && currentTourToken != _lastEnsuredTourToken) {
      _lastEnsuredTourToken = currentTourToken;
      _scheduleEnsureVisible();
    } else if (currentTourToken == null) {
      _lastEnsuredTourToken = null;
    }

    final baseChild = CompositedTransformTarget(
      link: _layerLink,
      child: KeyedSubtree(
        key: _targetKey,
        child: IgnorePointer(
          ignoring: showInlineHelpOverlay,
          child: widget.child,
        ),
      ),
    );

    if (!showInlineHelpOverlay) {
      return baseChild;
    }

    return Stack(
      fit: StackFit.passthrough,
      children: [
        baseChild,
        Positioned.fill(
          child: _InlineHelpTargetOverlay(
            spec: widget.spec,
            borderRadius: widget.borderRadius,
            isCurrentTourStep: isCurrentTourStep,
            onTap: helpModeEnabled && activeTour == null
                ? () => showAppHelpTargetSheet(
                      context,
                      ref,
                      spec: widget.spec,
                    )
                : null,
          ),
        ),
      ],
    );
  }
}

class AppHelpOverlay extends ConsumerWidget {
  const AppHelpOverlay({
    super.key,
    required this.surface,
  });

  final AppHelpSurfaceId surface;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final helpModeEnabled = ref.watch(appHelpModeEnabledProvider);
    final activeTour = ref.watch(appHelpCurrentSurfaceTourProvider(surface));
    if (!helpModeEnabled && activeTour == null) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            ignoring: activeTour == null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: activeTour == null ? null : () {},
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.scrim.withValues(
                        alpha: activeTour == null ? 0.08 : 0.14,
                      ),
                ),
              ),
            ),
          ),
        ),
        if (activeTour != null) _AppHelpTourDemoOverlay(surface: surface),
        if (activeTour != null) _AppHelpTourOverlayCard(surface: surface),
      ],
    );
  }
}

Future<void> showAppHelpTargetSheet(
  BuildContext context,
  WidgetRef ref, {
  required AppHelpTargetSpec spec,
}) async {
  final completedTours = ref.read(appHelpCompletedToursProvider);
  final hasTour = spec.tourId != null;
  final replaying = hasTour && completedTours.contains(spec.tourId);

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(spec.icon, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      spec.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                spec.description,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              _HelpBodySection(
                label: 'When to use it',
                text: spec.whenToUse,
              ),
              const SizedBox(height: 10),
              _HelpBodySection(
                label: 'What happens',
                text: spec.whatHappens,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (hasTour)
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await ref
                            .read(appHelpControllerProvider)
                            .startTour(spec.tourId!);
                      },
                      icon: const Icon(Icons.play_circle_outline),
                      label: Text(
                        replaying ? 'Replay walkthrough' : 'Start walkthrough',
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class AppHelpPreferencesBridge extends ConsumerStatefulWidget {
  const AppHelpPreferencesBridge({super.key});

  @override
  ConsumerState<AppHelpPreferencesBridge> createState() =>
      _AppHelpPreferencesBridgeState();
}

class _AppHelpPreferencesBridgeState
    extends ConsumerState<AppHelpPreferencesBridge> {
  String? _hydratedUserId;

  @override
  Widget build(BuildContext context) {
    final scopeUserId = ref.watch(boardScopeUserIdProvider);
    final preferencesAsync = ref.watch(appHelpPreferencesProvider);
    final preferences = preferencesAsync.valueOrNull;
    if (preferences != null && _hydratedUserId != scopeUserId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(appHelpShowFloatingButtonProvider.notifier).state =
            preferences.showFloatingHelpButton;
        ref.read(appHelpCompletedToursProvider.notifier).state =
            preferences.completedTours;
        _hydratedUserId = scopeUserId;
      });
    }
    return const SizedBox.shrink();
  }
}

class _InlineHelpTargetOverlay extends StatelessWidget {
  const _InlineHelpTargetOverlay({
    required this.spec,
    required this.borderRadius,
    required this.isCurrentTourStep,
    required this.onTap,
  });

  final AppHelpTargetSpec spec;
  final BorderRadius borderRadius;
  final bool isCurrentTourStep;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlightColor = isCurrentTourStep
        ? theme.colorScheme.primary
        : theme.colorScheme.secondary;

    return GestureDetector(
      key: ValueKey('help-target-${spec.id.key}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          color:
              highlightColor.withValues(alpha: isCurrentTourStep ? 0.14 : 0.08),
          border: Border.all(
            color: highlightColor.withValues(
              alpha: isCurrentTourStep ? 0.95 : 0.65,
            ),
            width: isCurrentTourStep ? 2.2 : 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: highlightColor.withValues(
                alpha: isCurrentTourStep ? 0.22 : 0.12,
              ),
              blurRadius: isCurrentTourStep ? 16 : 10,
              spreadRadius: isCurrentTourStep ? 2 : 1,
            ),
          ],
        ),
      ),
    );
  }
}

class _AppHelpTourOverlayCard extends ConsumerWidget {
  const _AppHelpTourOverlayCard({
    required this.surface,
  });

  final AppHelpSurfaceId surface;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTour = ref.watch(appHelpCurrentSurfaceTourProvider(surface));
    final definition = ref.watch(appHelpCurrentTourDefinitionProvider);
    final step = ref.watch(appHelpCurrentTourStepProvider);
    if (activeTour == null || definition == null || step == null) {
      return const SizedBox.shrink();
    }

    final isLastStep = activeTour.stepIndex >= definition.steps.length - 1;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: Card(
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    definition.title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    step.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(step.description),
                  const SizedBox(height: 10),
                  _HelpBodySection(
                    label: 'Watch for',
                    text: step.tryThis,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        'Step ${activeTour.stepIndex + 1} of ${definition.steps.length}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const Spacer(),
                      if (activeTour.stepIndex > 0)
                        TextButton(
                          onPressed: () {
                            ref.read(appHelpControllerProvider).retreatTour();
                          },
                          child: const Text('Back'),
                        ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          ref.read(appHelpControllerProvider).finishTour();
                        },
                        child: const Text('Close'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          ref.read(appHelpControllerProvider).advanceTour();
                        },
                        child: Text(isLastStep ? 'Done' : 'Next'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppHelpTourDemoOverlay extends ConsumerWidget {
  const _AppHelpTourDemoOverlay({
    required this.surface,
  });

  final AppHelpSurfaceId surface;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTour = ref.watch(appHelpCurrentSurfaceTourProvider(surface));
    final step = ref.watch(appHelpCurrentTourStepProvider);
    final visibleTargets = ref.watch(appHelpVisibleTargetsProvider);
    if (activeTour == null || step == null) {
      return const SizedBox.shrink();
    }

    final target = visibleTargets[step.targetId.key];
    if (target == null) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: CompositedTransformFollower(
          link: target.link,
          showWhenUnlinked: false,
          child: SizedBox(
            width: target.size.width,
            height: target.size.height,
            child: _AppHelpDemoCue(step: step, targetSize: target.size),
          ),
        ),
      ),
    );
  }
}

class _AppHelpDemoCue extends StatefulWidget {
  const _AppHelpDemoCue({
    required this.step,
    required this.targetSize,
  });

  final AppHelpTourStep step;
  final Size targetSize;

  @override
  State<_AppHelpDemoCue> createState() => _AppHelpDemoCueState();
}

class _AppHelpDemoCueState extends State<_AppHelpDemoCue>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant _AppHelpDemoCue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.step.demoKind != widget.step.demoKind) {
      _controller
        ..stop()
        ..forward(from: 0)
        ..repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return switch (widget.step.demoKind) {
          AppHelpTourDemoKind.pulse => _PulseDemoCue(progress: t),
          AppHelpTourDemoKind.tap => _TapDemoCue(
              progress: t,
              targetSize: widget.targetSize,
            ),
          AppHelpTourDemoKind.swipeHorizontal => _SwipeHorizontalDemoCue(
              progress: t,
              targetSize: widget.targetSize,
            ),
          AppHelpTourDemoKind.dragToRing => _DragToRingDemoCue(
              progress: t,
              targetSize: widget.targetSize,
            ),
          AppHelpTourDemoKind.slideUp => _SlideUpDemoCue(
              progress: t,
              targetSize: widget.targetSize,
            ),
        };
      },
    );
  }
}

class _PulseDemoCue extends StatelessWidget {
  const _PulseDemoCue({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final eased = Curves.easeInOut.transform(
      0.5 - (math.cos(progress * math.pi * 2) / 2),
    );
    return Center(
      child: Container(
        width: 54 + (18 * eased),
        height: 54 + (18 * eased),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.primary.withValues(
                alpha: 0.16 + (0.08 * eased),
              ),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(
                  alpha: 0.55 + (0.25 * eased),
                ),
            width: 1.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withValues(
                    alpha: 0.14 + (0.08 * eased),
                  ),
              blurRadius: 18 + (10 * eased),
            ),
          ],
        ),
        child: const Icon(Icons.touch_app_outlined),
      ),
    );
  }
}

class _TapDemoCue extends StatelessWidget {
  const _TapDemoCue({
    required this.progress,
    required this.targetSize,
  });

  final double progress;
  final Size targetSize;

  @override
  Widget build(BuildContext context) {
    final ripple = Curves.easeOut.transform(progress);
    final left = _safeClamp(targetSize.width * 0.62, 18, targetSize.width - 54);
    final top =
        _safeClamp(targetSize.height * 0.34, 12, targetSize.height - 54);
    return Stack(
      children: [
        Positioned(
          left: left - (14 * ripple),
          top: top - (14 * ripple),
          child: Container(
            width: 44 + (28 * ripple),
            height: 44 + (28 * ripple),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withValues(
                      alpha: 0.36 * (1 - ripple),
                    ),
                width: 2,
              ),
            ),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: _DemoGestureChip(
            icon: Icons.touch_app_outlined,
            label: 'Tap',
          ),
        ),
      ],
    );
  }
}

class _SwipeHorizontalDemoCue extends StatelessWidget {
  const _SwipeHorizontalDemoCue({
    required this.progress,
    required this.targetSize,
  });

  final double progress;
  final Size targetSize;

  @override
  Widget build(BuildContext context) {
    final travel = _safeClamp(targetSize.width - 120, 0, targetSize.width);
    final pingPong = 0.5 - (math.cos(progress * math.pi * 2) / 2);
    final x = 24 + (travel * pingPong);
    final y = _safeClamp(targetSize.height * 0.36, 10, targetSize.height - 48);
    return Stack(
      children: [
        Positioned(
          left: 18,
          right: 18,
          top: y + 18,
          child: Container(
            height: 2,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          ),
        ),
        Positioned(
          left: x,
          top: y,
          child: _DemoGestureChip(
            icon: Icons.swipe_outlined,
            label: 'Swipe',
          ),
        ),
      ],
    );
  }
}

class _DragToRingDemoCue extends StatelessWidget {
  const _DragToRingDemoCue({
    required this.progress,
    required this.targetSize,
  });

  final double progress;
  final Size targetSize;

  @override
  Widget build(BuildContext context) {
    final curve = Curves.easeInOutCubic.transform(progress);
    final start = Offset(targetSize.width * 0.5, targetSize.height * 0.72);
    final end = Offset(targetSize.width * 0.24, targetSize.height * 0.38);
    final position = Offset.lerp(start, end, curve)!;

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _DemoPathPainter(
              start: start,
              end: end,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        Positioned(
          left: position.dx - 44,
          top: position.dy - 24,
          child: Opacity(
            opacity: 0.86,
            child: _DemoGhostCard(progress: curve),
          ),
        ),
      ],
    );
  }
}

class _SlideUpDemoCue extends StatelessWidget {
  const _SlideUpDemoCue({
    required this.progress,
    required this.targetSize,
  });

  final double progress;
  final Size targetSize;

  @override
  Widget build(BuildContext context) {
    final curve = Curves.easeInOutCubic.transform(progress);
    final bottom = 14 + (targetSize.height * 0.36 * curve);
    final centerX = targetSize.width / 2;
    return Stack(
      children: [
        Positioned(
          left: centerX - 1,
          bottom: 18,
          child: Container(
            width: 2,
            height: targetSize.height * 0.42,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          ),
        ),
        Positioned(
          left: centerX - 40,
          bottom: bottom,
          child: _DemoGestureChip(
            icon: Icons.swipe_up_outlined,
            label: 'Open tray',
          ),
        ),
      ],
    );
  }
}

double _safeClamp(double value, double minValue, double maxValue) {
  final lower = math.min(minValue, maxValue);
  final upper = math.max(minValue, maxValue);
  return value.clamp(lower, upper).toDouble();
}

class _DemoGestureChip extends StatelessWidget {
  const _DemoGestureChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 6,
      color: theme.colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.onPrimaryContainer),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DemoGhostCard extends StatelessWidget {
  const _DemoGhostCard({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Transform.rotate(
      angle: -0.06 + (0.12 * progress),
      child: Material(
        elevation: 10,
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 88,
          height: 48,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.24),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 7,
                      width: 44,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 6,
                      width: 26,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DemoPathPainter extends CustomPainter {
  const _DemoPathPainter({
    required this.start,
    required this.end,
    required this.color,
  });

  final Offset start;
  final Offset end;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(
        (start.dx + end.dx) / 2,
        math.min(start.dy, end.dy) - 72,
        end.dx,
        end.dy,
      );

    final paint = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DemoPathPainter oldDelegate) {
    return start != oldDelegate.start ||
        end != oldDelegate.end ||
        color != oldDelegate.color;
  }
}

class _HelpBodySection extends StatelessWidget {
  const _HelpBodySection({
    required this.label,
    required this.text,
  });

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        Text(text),
      ],
    );
  }
}
