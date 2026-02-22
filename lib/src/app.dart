import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/plan_done_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/board/presentation/board_page.dart';

class PlanDoneApp extends ConsumerWidget {
  const PlanDoneApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTheme = ref.watch(themeControllerProvider).valueOrNull ?? PlanDoneThemeKey.calmFocus;

    return MaterialApp(
      title: 'PlanDone',
      debugShowCheckedModeBanner: false,
      theme: PlanDoneThemes.resolve(selectedTheme, brightness: Brightness.light),
      darkTheme: PlanDoneThemes.resolve(selectedTheme, brightness: Brightness.dark),
      themeMode: ThemeMode.system,
      home: const BoardPage(),
    );
  }
}
