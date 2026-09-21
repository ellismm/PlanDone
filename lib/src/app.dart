import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_routes.dart';
import 'core/branding/plan_done_branding.dart';
import 'core/notifications/local_notification_delivery.dart';
import 'core/notifications/push_notification_service.dart';
import 'core/runtime/runtime_flags.dart';
import 'core/theme/plan_done_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/domain/models/auth_user.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'features/board/presentation/board_controller.dart';
import 'features/auth/presentation/auth_page.dart';
import 'features/ai_planning/presentation/ai_planning_page.dart';
import 'features/board/domain/models/board_scheduled_reminder.dart';
import 'features/board/presentation/board_configuration_page.dart';
import 'features/board/presentation/board_flow_page.dart';
import 'features/board/presentation/board_insights_page.dart';
import 'features/board/presentation/board_page.dart';
import 'features/board/presentation/board_planning_entry_page.dart';

class PlanDoneLaunchAnimationConfig {
  const PlanDoneLaunchAnimationConfig({
    required this.enabled,
    this.sequenceDuration = const Duration(milliseconds: 5300),
    this.reducedMotionDuration = const Duration(milliseconds: 800),
  });

  final bool enabled;
  final Duration sequenceDuration;
  final Duration reducedMotionDuration;
}

final launchAnimationConfigProvider = Provider<PlanDoneLaunchAnimationConfig>(
  (ref) {
    final bindingName = WidgetsBinding.instance.runtimeType.toString();
    final shouldDisable = isFlutterTestRuntime || bindingName.contains('Test');
    return PlanDoneLaunchAnimationConfig(enabled: !shouldDisable);
  },
);

class PlanDoneApp extends ConsumerWidget {
  const PlanDoneApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTheme = ref.watch(themeControllerProvider).valueOrNull ??
        PlanDoneThemeKey.calmFocus;
    final authSessionAsync = ref.watch(authSessionProvider);
    final appKey =
        ValueKey(authSessionAsync.asData?.value?.user.uid ?? 'guest');

    final app = MaterialApp(
      key: appKey,
      title: 'PlanDone',
      debugShowCheckedModeBanner: false,
      theme:
          PlanDoneThemes.resolve(selectedTheme, brightness: Brightness.light),
      darkTheme:
          PlanDoneThemes.resolve(selectedTheme, brightness: Brightness.dark),
      themeMode: ThemeMode.system,
      initialRoute: AppRoutes.workspace,
      routes: {
        AppRoutes.workspace: (_) => const _AuthGuardedPage(child: BoardPage()),
        AppRoutes.flow: (_) => const _AuthGuardedPage(child: BoardFlowPage()),
        AppRoutes.insights: (_) =>
            const _AuthGuardedPage(child: BoardInsightsPage()),
        AppRoutes.boardConfiguration: (_) =>
            const _AuthGuardedPage(child: BoardConfigurationPage()),
        AppRoutes.planning: (_) =>
            const _AuthGuardedPage(child: BoardPlanningEntryPage()),
        AppRoutes.aiPlanning: (_) =>
            const _AuthGuardedPage(child: AiPlanningPage()),
      },
    );
    final bindingName = WidgetsBinding.instance.runtimeType.toString();
    final shouldSkipReminderBootstrap =
        isFlutterTestRuntime || bindingName.contains('Test');
    Widget wrapped =
        shouldSkipReminderBootstrap ? app : _LocalReminderBootstrap(child: app);
    if (useFirebasePush) {
      wrapped = _PushNotificationBootstrap(child: wrapped);
    }
    return _PlanDoneLaunchGate(
      config: ref.watch(launchAnimationConfigProvider),
      child: wrapped,
    );
  }
}

class _AuthGuardedPage extends ConsumerWidget {
  const _AuthGuardedPage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authSessionAsync = ref.watch(authSessionProvider);
    return authSessionAsync.when(
      data: (session) => session == null
          ? const AuthPage()
          : _BiometricSessionGuard(
              session: session,
              child: _ReminderNotificationActionBootstrap(
                session: session,
                child: child,
              ),
            ),
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        body: Center(child: Text('Auth bootstrap error: $error')),
      ),
    );
  }
}

class _BiometricSessionGuard extends ConsumerStatefulWidget {
  const _BiometricSessionGuard({
    required this.session,
    required this.child,
  });

  final AuthSession session;
  final Widget child;

  @override
  ConsumerState<_BiometricSessionGuard> createState() =>
      _BiometricSessionGuardState();
}

class _BiometricSessionGuardState
    extends ConsumerState<_BiometricSessionGuard> {
  bool _isChecking = true;
  bool _isLocked = false;
  bool _isUnlocking = false;
  String? _unlockError;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshGuardState());
  }

  @override
  void didUpdateWidget(covariant _BiometricSessionGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.user.uid != widget.session.user.uid) {
      unawaited(_refreshGuardState());
    }
  }

  Future<void> _refreshGuardState() async {
    final requiresUnlock = await ref
        .read(authControllerProvider)
        .requiresBiometricQuickUnlock(widget.session);
    if (!mounted) return;
    setState(() {
      _isChecking = false;
      _isLocked = requiresUnlock;
      _unlockError = null;
    });
  }

  Future<void> _unlock() async {
    setState(() {
      _isUnlocking = true;
      _unlockError = null;
    });
    final unlocked = await ref
        .read(authControllerProvider)
        .unlockWithBiometrics(widget.session);
    if (!mounted) return;
    setState(() {
      _isUnlocking = false;
      _isLocked = !unlocked;
      _unlockError = unlocked
          ? null
          : 'Fingerprint unlock was canceled or failed. Try again or sign out.';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isLocked) {
      return widget.child;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Unlock PlanDone'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: PlanDoneBrandMark(size: 56)),
                  const SizedBox(height: 16),
                  Text(
                    'Unlock with fingerprint',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Use your device biometric unlock to continue as ${widget.session.user.displayName ?? widget.session.user.email ?? 'your account'}.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (_unlockError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _unlockError!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isUnlocking ? null : _unlock,
                    icon: const Icon(Icons.fingerprint),
                    label: Text(
                      _isUnlocking ? 'Unlocking...' : 'Unlock with fingerprint',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _isUnlocking
                        ? null
                        : () => ref.read(authControllerProvider).signOut(),
                    child: const Text('Sign out instead'),
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

class _PushNotificationBootstrap extends ConsumerStatefulWidget {
  const _PushNotificationBootstrap({required this.child});

  final Widget child;

  @override
  ConsumerState<_PushNotificationBootstrap> createState() =>
      _PushNotificationBootstrapState();
}

class _PushNotificationBootstrapState
    extends ConsumerState<_PushNotificationBootstrap> {
  ProviderSubscription<AsyncValue<AuthSession?>>? _authListener;

  @override
  void initState() {
    super.initState();
    _authListener = ref.listenManual<AsyncValue<AuthSession?>>(
      authSessionProvider,
      (_, next) {
        final uid = next.valueOrNull?.user.uid;
        unawaited(
          ref.read(pushNotificationServiceProvider).syncForUser(uid),
        );
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _authListener?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _LocalReminderBootstrap extends ConsumerStatefulWidget {
  const _LocalReminderBootstrap({required this.child});

  final Widget child;

  @override
  ConsumerState<_LocalReminderBootstrap> createState() =>
      _LocalReminderBootstrapState();
}

class _LocalReminderBootstrapState
    extends ConsumerState<_LocalReminderBootstrap> {
  ProviderSubscription<AsyncValue<List<BoardScheduledReminder>>>?
      _reminderListener;

  @override
  void initState() {
    super.initState();
    _reminderListener =
        ref.listenManual<AsyncValue<List<BoardScheduledReminder>>>(
      scheduledBoardRemindersProvider,
      (_, next) async {
        final reminders = next.valueOrNull;
        if (reminders == null) return;
        final delivery = ref.read(localNotificationDeliveryProvider);
        if (reminders.isNotEmpty) {
          await delivery.ensurePermissionRequested();
        }
        await delivery.syncScheduledReminders(reminders);
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _reminderListener?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _ReminderNotificationActionBootstrap extends ConsumerStatefulWidget {
  const _ReminderNotificationActionBootstrap({
    required this.session,
    required this.child,
  });

  final AuthSession session;
  final Widget child;

  @override
  ConsumerState<_ReminderNotificationActionBootstrap> createState() =>
      _ReminderNotificationActionBootstrapState();
}

class _ReminderNotificationActionBootstrapState
    extends ConsumerState<_ReminderNotificationActionBootstrap>
    with WidgetsBindingObserver {
  bool _isDraining = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_drainPendingActions());
  }

  @override
  void didUpdateWidget(
    covariant _ReminderNotificationActionBootstrap oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.user.uid != widget.session.user.uid) {
      unawaited(_drainPendingActions());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_drainPendingActions());
    }
  }

  Future<void> _drainPendingActions() async {
    if (_isDraining) return;
    _isDraining = true;
    try {
      final actions = await ref
          .read(localNotificationDeliveryProvider)
          .drainPendingActions();
      for (final action in actions) {
        if (!mounted) return;
        switch (action.kind) {
          case PendingReminderNotificationActionKind.done:
            await ref.read(boardControllerProvider).completeReminderAsDone(
                  boardId: action.boardId,
                  itemId: action.itemId,
                );
            break;
          case PendingReminderNotificationActionKind.snooze:
            await ref.read(boardControllerProvider).snoozeReminder(
                  reminderId: action.reminderId,
                );
            break;
        }
      }
    } finally {
      _isDraining = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _PlanDoneLaunchGate extends StatefulWidget {
  const _PlanDoneLaunchGate({
    required this.config,
    required this.child,
  });

  final PlanDoneLaunchAnimationConfig config;
  final Widget child;

  @override
  State<_PlanDoneLaunchGate> createState() => _PlanDoneLaunchGateState();
}

class _PlanDoneLaunchGateState extends State<_PlanDoneLaunchGate>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  bool _dismissed = false;
  late final bool _reduceMotion;

  @override
  void initState() {
    super.initState();
    _reduceMotion = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (!widget.config.enabled) {
      _dismissed = true;
      return;
    }

    _controller = AnimationController(
      vsync: this,
      duration: _reduceMotion
          ? widget.config.reducedMotionDuration
          : widget.config.sequenceDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _dismissed = true);
        }
      });
    unawaited(_controller!.forward());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  double _interval(
    double begin,
    double end, {
    Curve curve = Curves.easeOutCubic,
  }) {
    final controller = _controller;
    if (controller == null) return 1;
    final raw = ((controller.value - begin) / (end - begin)).clamp(0.0, 1.0);
    return curve.transform(raw);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed || !widget.config.enabled || _controller == null) {
      return widget.child;
    }

    return Stack(
      alignment: Alignment.topLeft,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: false,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: AnimatedBuilder(
                animation: _controller!,
                builder: (context, _) {
                  final leftReveal =
                      _reduceMotion ? 1.0 : _interval(0.146, 0.341);
                  final middleReveal =
                      _reduceMotion ? 1.0 : _interval(0.292, 0.471);
                  final lowerRightReveal =
                      _reduceMotion ? 1.0 : _interval(0.438, 0.617);
                  final upperRightReveal =
                      _reduceMotion ? 1.0 : _interval(0.552, 0.698);
                  final checkReveal =
                      _reduceMotion ? 1.0 : _interval(0.681, 0.763);
                  final planWordReveal =
                      _reduceMotion ? 1.0 : _interval(0.00, 0.146);
                  final doneWordReveal =
                      _reduceMotion ? 1.0 : _interval(0.681, 0.763);
                  final overlayOpacity = 1 -
                      (_reduceMotion
                          ? _interval(0.36, 1.00, curve: Curves.easeInOut)
                          : _interval(
                              0.919,
                              1.00,
                              curve: Curves.easeInOutCubic,
                            ));

                  return Opacity(
                    key: const ValueKey('launch-overlay'),
                    opacity: overlayOpacity.clamp(0, 1),
                    child: ColoredBox(
                      color: const Color(0xFFF4F7F5),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          const sceneWidth = 280.0;
                          const sceneHeight = 248.0;
                          const markWidth = 168.0;
                          const leftTop = 18.0;
                          const middleTop = 18.0;
                          const lowerRightTop = 58.0;
                          const upperRightTop = 18.0;
                          const leftHeight = 124.0;
                          const middleHeight = 124.0;
                          const lowerRightHeight = 84.0;
                          const upperRightHeight = 40.0;
                          const wordTop = 170.0;

                          final sceneTop =
                              (constraints.maxHeight - sceneHeight) / 2;
                          final sceneLeft =
                              (constraints.maxWidth - sceneWidth) / 2;
                          const markTop = 0.0;
                          final markLeft = (sceneWidth - markWidth) / 2;
                          final wordStyle = _launchWordStyle(
                            const Color(0xFF1C1C1E),
                          );
                          final planPainter = TextPainter(
                            text: TextSpan(text: 'Plan', style: wordStyle),
                            textDirection: TextDirection.ltr,
                          )..layout();
                          final donePainter = TextPainter(
                            text: TextSpan(text: 'Done', style: wordStyle),
                            textDirection: TextDirection.ltr,
                          )..layout();
                          final planWidth = planPainter.width;
                          final doneWidth = donePainter.width;
                          final totalWordWidth = planWidth + doneWidth;
                          final wordmarkLeft =
                              (sceneWidth - totalWordWidth) / 2;
                          final planLeft = wordmarkLeft;
                          final doneLeft = wordmarkLeft + planWidth;

                          double travelFromBottom({
                            required double pieceTop,
                          }) {
                            final finalTop = sceneTop + markTop + pieceTop;
                            return constraints.maxHeight - finalTop + 32;
                          }

                          double travelFromTop({
                            required double pieceTop,
                            required double pieceHeight,
                          }) {
                            final finalBottom =
                                sceneTop + markTop + pieceTop + pieceHeight;
                            return -(finalBottom + 32);
                          }

                          double travelFromLeft({
                            required double pieceLeft,
                            required double pieceWidth,
                          }) {
                            final finalLeft = sceneLeft + pieceLeft;
                            return -(finalLeft + pieceWidth + 120);
                          }

                          double travelFromRight({
                            required double pieceLeft,
                          }) {
                            final finalLeft = sceneLeft + pieceLeft;
                            return constraints.maxWidth - finalLeft + 120;
                          }

                          return Center(
                            child: SizedBox(
                              width: sceneWidth,
                              height: sceneHeight,
                              child: Stack(
                                alignment: Alignment.topLeft,
                                children: [
                                  Positioned(
                                    left: markLeft + 10,
                                    top: markTop + leftTop,
                                    child: _LaunchSlidePiece(
                                      progress: leftReveal,
                                      initialOffsetY: travelFromBottom(
                                        pieceTop: leftTop,
                                      ),
                                      child: _LaunchColumn(
                                        width: 26,
                                        height: leftHeight,
                                        color: const Color(0xFF111111),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: markLeft + 56,
                                    top: markTop + middleTop,
                                    child: _LaunchSlidePiece(
                                      progress: middleReveal,
                                      initialOffsetY: travelFromTop(
                                        pieceTop: middleTop,
                                        pieceHeight: middleHeight,
                                      ),
                                      child: _LaunchColumn(
                                        width: 26,
                                        height: middleHeight,
                                        color: const Color(0xFF5A5A5A),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: markLeft + 102,
                                    top: markTop + lowerRightTop,
                                    child: _LaunchSlidePiece(
                                      progress: lowerRightReveal,
                                      initialOffsetY: travelFromBottom(
                                        pieceTop: lowerRightTop,
                                      ),
                                      child: _LaunchColumn(
                                        width: 26,
                                        height: lowerRightHeight,
                                        color: const Color(0xFF111111),
                                        radius: 13,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: markLeft + 102,
                                    top: markTop + upperRightTop,
                                    child: _LaunchSlidePiece(
                                      progress: upperRightReveal,
                                      initialOffsetY: travelFromTop(
                                        pieceTop: upperRightTop,
                                        pieceHeight: upperRightHeight,
                                      ),
                                      child: _LaunchColumn(
                                        width: 26,
                                        height: upperRightHeight,
                                        color: const Color(0xFF1CB5AD),
                                        radius: 13,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: markLeft + 100,
                                    top: markTop + 29,
                                    child: Opacity(
                                      opacity: checkReveal,
                                      child: Transform.scale(
                                        scale: 0.7 + (checkReveal * 0.3),
                                        child: const Icon(
                                          Icons.check_rounded,
                                          color: Colors.white,
                                          size: 28,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: planLeft,
                                    top: wordTop,
                                    child: _LaunchSlidePiece(
                                      progress: planWordReveal,
                                      initialOffsetX: travelFromLeft(
                                        pieceLeft: planLeft,
                                        pieceWidth: planWidth,
                                      ),
                                      child: const _LaunchWord(
                                        label: 'Plan',
                                        color: Color(0xFF1C1C1E),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: doneLeft,
                                    top: wordTop,
                                    child: _LaunchSlidePiece(
                                      progress: doneWordReveal,
                                      initialOffsetX: travelFromRight(
                                        pieceLeft: doneLeft,
                                      ),
                                      child: const _LaunchWord(
                                        label: 'Done',
                                        color: Color(0xFF1CB5AD),
                                      ),
                                    ),
                                  ),
                                  if (_reduceMotion)
                                    Positioned.fill(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: const [
                                          PlanDoneBrandMark(size: 132),
                                          SizedBox(height: 4),
                                          _LaunchWordmark(),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LaunchSlidePiece extends StatelessWidget {
  const _LaunchSlidePiece({
    required this.progress,
    this.initialOffsetX = 0,
    this.initialOffsetY = 0,
    required this.child,
  });

  final double progress;
  final double initialOffsetX;
  final double initialOffsetY;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final clampedProgress = progress.clamp(0.0, 1.0).toDouble();
    return Opacity(
      opacity: clampedProgress,
      child: Transform.translate(
        offset: Offset(
          initialOffsetX * (1 - clampedProgress),
          initialOffsetY * (1 - clampedProgress),
        ),
        child: child,
      ),
    );
  }
}

class _LaunchColumn extends StatelessWidget {
  const _LaunchColumn({
    required this.width,
    required this.height,
    required this.color,
    this.radius = 14,
  });

  final double width;
  final double height;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _LaunchWordmark extends StatelessWidget {
  const _LaunchWordmark();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LaunchWord(label: 'Plan', color: Color(0xFF1C1C1E)),
        _LaunchWord(label: 'Done', color: Color(0xFF1CB5AD)),
      ],
    );
  }
}

class _LaunchWord extends StatelessWidget {
  const _LaunchWord({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: _launchWordStyle(color),
    );
  }
}

TextStyle _launchWordStyle(Color color) {
  return TextStyle(
    color: color,
    fontSize: 34,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.2,
    height: 1,
  );
}
