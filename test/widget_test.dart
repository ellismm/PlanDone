// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import 'package:plandone/src/core/outbox/in_memory_outbox_queue.dart';
import 'package:plandone/src/core/theme/theme_controller.dart';
import 'package:plandone/src/core/theme/theme_settings_repository.dart';
import 'package:plandone/src/app.dart';
import 'package:plandone/src/features/auth/data/data_sources/in_memory_auth_data_source.dart';
import 'package:plandone/src/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:plandone/src/features/auth/domain/models/auth_user.dart';
import 'package:plandone/src/features/auth/presentation/auth_controller.dart';
import 'package:plandone/src/features/board/data/local/in_memory_local_board_store.dart';
import 'package:plandone/src/features/board/presentation/board_controller.dart';

Widget _buildAppWithAuthSession(AuthSession? initialSession) {
  final userId = initialSession?.user.uid ?? 'guest';
  return ProviderScope(
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
    ],
    child: const PlanDoneApp(),
  );
}

void main() {
  testWidgets('PlanDone app shows auth flow when unauthenticated',
      (WidgetTester tester) async {
    await tester.pumpWidget(_buildAppWithAuthSession(null));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Sign in to PlanDone'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byTooltip('Sync now'), findsNothing);
  });

  testWidgets('PlanDone app renders board shell for authenticated session',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _buildAppWithAuthSession(
        const AuthSession(
          user: AuthUser(
            uid: 'user-1',
            email: 'user-1@plandone.dev',
            displayName: 'User One',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Workspace'), findsWidgets);
    expect(find.byTooltip('Theme'), findsOneWidget);
    expect(find.byTooltip('Sync now'), findsOneWidget);
    expect(find.byTooltip('Sign out'), findsOneWidget);
    expect(find.byTooltip('Search items'), findsOneWidget);
    expect(find.byTooltip('Quick capture'), findsOneWidget);
    expect(find.byTooltip('Show inbox'), findsOneWidget);
    expect(find.text('Add Item'), findsOneWidget);
  });

  testWidgets('primary navigation switches between workspace routes',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _buildAppWithAuthSession(
        const AuthSession(
          user: AuthUser(
            uid: 'user-1',
            email: 'user-1@plandone.dev',
            displayName: 'User One',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Workspace'), findsWidgets);

    await tester.tap(find.text('Configuration'));
    await tester.pumpAndSettle();
    expect(find.text('Board Configuration'), findsOneWidget);
    expect(find.text('Board Scope'), findsOneWidget);

    await tester.tap(find.text('Planning'));
    await tester.pumpAndSettle();
    expect(find.text('Planning Entry Point'), findsOneWidget);

    await tester.tap(find.text('Workspace'));
    await tester.pumpAndSettle();
    expect(find.text('Add Item'), findsOneWidget);
  });
}
