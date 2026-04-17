import 'package:flutter/material.dart';

import 'board_controller.dart';

String boardPlanningViewLabel(BoardPlanningView view) {
  return switch (view) {
    BoardPlanningView.kanban => 'Kanban',
    BoardPlanningView.hierarchy => 'Hierarchy',
    BoardPlanningView.backlog => 'Backlog',
    BoardPlanningView.focus => 'Focus',
    BoardPlanningView.calendar => 'Calendar',
  };
}

IconData boardPlanningViewIcon(BoardPlanningView view) {
  return switch (view) {
    BoardPlanningView.kanban => Icons.view_kanban_outlined,
    BoardPlanningView.hierarchy => Icons.account_tree_outlined,
    BoardPlanningView.backlog => Icons.list_alt_outlined,
    BoardPlanningView.focus => Icons.filter_center_focus_outlined,
    BoardPlanningView.calendar => Icons.calendar_month_outlined,
  };
}

IconData boardPlanningViewSelectedIcon(BoardPlanningView view) {
  return switch (view) {
    BoardPlanningView.kanban => Icons.view_kanban,
    BoardPlanningView.hierarchy => Icons.account_tree,
    BoardPlanningView.backlog => Icons.list_alt,
    BoardPlanningView.focus => Icons.filter_center_focus,
    BoardPlanningView.calendar => Icons.calendar_month,
  };
}
