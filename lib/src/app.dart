import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_routes.dart';
import 'core/notifications/push_notification_service.dart';
import 'core/runtime/runtime_flags.dart';
import 'core/theme/plan_done_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/domain/models/auth_user.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'features/auth/presentation/auth_page.dart';
import 'features/board/presentation/board_configuration_page.dart';
import 'features/board/presentation/board_page.dart';
import 'features/board/presentation/board_planning_entry_page.dart';

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
        AppRoutes.boardConfiguration: (_) =>
            const _AuthGuardedPage(child: BoardConfigurationPage()),
        AppRoutes.planning: (_) =>
            const _AuthGuardedPage(child: BoardPlanningEntryPage()),
      },
    );
    if (!useFirebasePush) return app;
    return _PushNotificationBootstrap(child: app);
  }
}

class _AuthGuardedPage extends ConsumerWidget {
  const _AuthGuardedPage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authSessionAsync = ref.watch(authSessionProvider);
    return authSessionAsync.when(
      data: (session) => session == null ? const AuthPage() : child,
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        body: Center(child: Text('Auth bootstrap error: $error')),
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
