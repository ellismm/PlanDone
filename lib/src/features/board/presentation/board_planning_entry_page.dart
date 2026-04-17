import 'package:flutter/material.dart';

import '../../../app_routes.dart';

class BoardPlanningEntryPage extends StatefulWidget {
  const BoardPlanningEntryPage({super.key});

  @override
  State<BoardPlanningEntryPage> createState() => _BoardPlanningEntryPageState();
}

class _BoardPlanningEntryPageState extends State<BoardPlanningEntryPage> {
  bool _redirectScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_redirectScheduled) return;
    _redirectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppRoutes.workspace);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}
