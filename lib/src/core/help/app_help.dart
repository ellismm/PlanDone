import 'package:flutter/material.dart';

enum AppHelpSurfaceId {
  workspace,
  flow,
  insights,
  configuration,
}

enum AppHelpTourId {
  workspace,
  hierarchy,
  insights,
  configuration,
  flow,
  calendar,
}

class AppHelpTargetId {
  const AppHelpTargetId(this.surface, this.value);

  final AppHelpSurfaceId surface;
  final String value;

  String get key => '${surface.name}::$value';

  @override
  bool operator ==(Object other) {
    return other is AppHelpTargetId &&
        other.surface == surface &&
        other.value == value;
  }

  @override
  int get hashCode => Object.hash(surface, value);
}

class AppHelpTargetSpec {
  const AppHelpTargetSpec({
    required this.id,
    required this.title,
    required this.description,
    required this.whenToUse,
    required this.whatHappens,
    this.icon = Icons.help_outline,
    this.tourId,
  });

  final AppHelpTargetId id;
  final String title;
  final String description;
  final String whenToUse;
  final String whatHappens;
  final IconData icon;
  final AppHelpTourId? tourId;
}

enum AppHelpTourDemoKind {
  pulse,
  tap,
  swipeHorizontal,
  dragToRing,
  slideUp,
}

class AppHelpTourStep {
  const AppHelpTourStep({
    required this.targetId,
    required this.title,
    required this.description,
    required this.tryThis,
    this.demoKind = AppHelpTourDemoKind.pulse,
  });

  final AppHelpTargetId targetId;
  final String title;
  final String description;
  final String tryThis;
  final AppHelpTourDemoKind demoKind;
}

class AppHelpTourDefinition {
  const AppHelpTourDefinition({
    required this.id,
    required this.surface,
    required this.title,
    required this.description,
    required this.steps,
  });

  final AppHelpTourId id;
  final AppHelpSurfaceId surface;
  final String title;
  final String description;
  final List<AppHelpTourStep> steps;
}

class AppHelpPreferences {
  const AppHelpPreferences({
    this.showFloatingHelpButton = false,
    this.completedTours = const <AppHelpTourId>{},
  });

  final bool showFloatingHelpButton;
  final Set<AppHelpTourId> completedTours;

  AppHelpPreferences copyWith({
    bool? showFloatingHelpButton,
    Set<AppHelpTourId>? completedTours,
  }) {
    return AppHelpPreferences(
      showFloatingHelpButton:
          showFloatingHelpButton ?? this.showFloatingHelpButton,
      completedTours: completedTours ?? this.completedTours,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'showFloatingHelpButton': showFloatingHelpButton,
      'completedTours': completedTours.map((tour) => tour.name).toList(),
    };
  }

  static AppHelpPreferences fromMap(Map<String, Object?>? map) {
    if (map == null) {
      return const AppHelpPreferences();
    }

    final completedTours = (map['completedTours'] as List?)
            ?.whereType<String>()
            .map(
              (name) =>
                  AppHelpTourId.values.where((entry) => entry.name == name),
            )
            .where((matches) => matches.isNotEmpty)
            .map((matches) => matches.first)
            .toSet() ??
        const <AppHelpTourId>{};

    return AppHelpPreferences(
      showFloatingHelpButton: map['showFloatingHelpButton'] == true,
      completedTours: completedTours,
    );
  }
}

class AppHelpTourProgress {
  const AppHelpTourProgress({
    required this.tourId,
    required this.stepIndex,
  });

  final AppHelpTourId tourId;
  final int stepIndex;

  AppHelpTourProgress copyWith({
    AppHelpTourId? tourId,
    int? stepIndex,
  }) {
    return AppHelpTourProgress(
      tourId: tourId ?? this.tourId,
      stepIndex: stepIndex ?? this.stepIndex,
    );
  }
}

abstract final class AppHelpTargetIds {
  static const workspaceControls =
      AppHelpTargetId(AppHelpSurfaceId.workspace, 'workspace-controls');
  static const workspaceCapture =
      AppHelpTargetId(AppHelpSurfaceId.workspace, 'workspace-capture');
  static const workspaceBoardScope =
      AppHelpTargetId(AppHelpSurfaceId.workspace, 'workspace-board-scope');
  static const workspaceViewPicker =
      AppHelpTargetId(AppHelpSurfaceId.workspace, 'workspace-view-picker');
  static const workspaceFilters =
      AppHelpTargetId(AppHelpSurfaceId.workspace, 'workspace-filters');
  static const workspaceReminders =
      AppHelpTargetId(AppHelpSurfaceId.workspace, 'workspace-reminders');
  static const workspaceSearch =
      AppHelpTargetId(AppHelpSurfaceId.workspace, 'workspace-search');
  static const workspaceTopFocus =
      AppHelpTargetId(AppHelpSurfaceId.workspace, 'workspace-top-focus');
  static const workspaceTopTools =
      AppHelpTargetId(AppHelpSurfaceId.workspace, 'workspace-top-tools');
  static const workspaceHierarchyControls = AppHelpTargetId(
    AppHelpSurfaceId.workspace,
    'workspace-hierarchy-controls',
  );
  static const workspaceKanbanSurface =
      AppHelpTargetId(AppHelpSurfaceId.workspace, 'workspace-kanban-surface');
  static const workspaceHierarchySurface = AppHelpTargetId(
    AppHelpSurfaceId.workspace,
    'workspace-hierarchy-surface',
  );
  static const workspaceInboxSurface =
      AppHelpTargetId(AppHelpSurfaceId.workspace, 'workspace-inbox-surface');
  static const calendarToolbar =
      AppHelpTargetId(AppHelpSurfaceId.workspace, 'calendar-toolbar');
  static const calendarSurface =
      AppHelpTargetId(AppHelpSurfaceId.workspace, 'calendar-surface');
  static const calendarUnscheduledTray = AppHelpTargetId(
    AppHelpSurfaceId.workspace,
    'calendar-unscheduled-tray',
  );
  static const flowControls =
      AppHelpTargetId(AppHelpSurfaceId.flow, 'flow-controls');
  static const flowPlayfield =
      AppHelpTargetId(AppHelpSurfaceId.flow, 'flow-playfield');
  static const flowTodayCount =
      AppHelpTargetId(AppHelpSurfaceId.flow, 'flow-today-count');
  static const flowActionRing =
      AppHelpTargetId(AppHelpSurfaceId.flow, 'flow-action-ring');
  static const insightsHeader =
      AppHelpTargetId(AppHelpSurfaceId.insights, 'insights-header');
  static const insightsAccomplished =
      AppHelpTargetId(AppHelpSurfaceId.insights, 'insights-accomplished');
  static const insightsMomentum =
      AppHelpTargetId(AppHelpSurfaceId.insights, 'insights-momentum');
  static const insightsBoardHealth =
      AppHelpTargetId(AppHelpSurfaceId.insights, 'insights-board-health');
  static const insightsAttention =
      AppHelpTargetId(AppHelpSurfaceId.insights, 'insights-attention');
  static const configurationBoardScope = AppHelpTargetId(
    AppHelpSurfaceId.configuration,
    'configuration-board-scope',
  );
  static const configurationBoardSettings = AppHelpTargetId(
    AppHelpSurfaceId.configuration,
    'configuration-board-settings',
  );
  static const configurationAccount = AppHelpTargetId(
    AppHelpSurfaceId.configuration,
    'configuration-account',
  );
  static const configurationColumns = AppHelpTargetId(
    AppHelpSurfaceId.configuration,
    'configuration-columns',
  );
  static const configurationHelp = AppHelpTargetId(
    AppHelpSurfaceId.configuration,
    'configuration-help',
  );
}

final appHelpFlowTour = AppHelpTourDefinition(
  id: AppHelpTourId.flow,
  surface: AppHelpSurfaceId.flow,
  title: 'Flow walkthrough',
  description:
      'Flow helps you sweep through open actions once per day, and this walkthrough moves the page into the right states while it explains each part.',
  steps: const [
    AppHelpTourStep(
      targetId: AppHelpTargetIds.flowControls,
      title: 'Set the lane you are sorting',
      description:
          'Use the top controls to choose board scope, item types, and whether motion stays on.',
      tryThis:
          'Watch the controls settle into a practical default: actions only, with motion on.',
      demoKind: AppHelpTourDemoKind.tap,
    ),
    AppHelpTourStep(
      targetId: AppHelpTargetIds.flowPlayfield,
      title: 'Read the floating playfield',
      description:
          'Cards in the playfield are the actions that still need a pass today.',
      tryThis:
          'Notice how the cards keep moving while the playfield stays open for quick decisions.',
      demoKind: AppHelpTourDemoKind.pulse,
    ),
    AppHelpTourStep(
      targetId: AppHelpTargetIds.flowActionRing,
      title: 'Sort a card with the decision ring',
      description:
          'When you drag a card, the ring becomes the hand-holding part of Flow: do it now, schedule it, move it, mark it done, or dismiss it for today.',
      tryThis:
          'Watch the demo drag path move a card toward one of the ring targets. That is the same motion you use yourself.',
      demoKind: AppHelpTourDemoKind.dragToRing,
    ),
    AppHelpTourStep(
      targetId: AppHelpTargetIds.flowTodayCount,
      title: 'Track what is left today',
      description:
          'This count shows how many Flow items still need a pass today. Once you act on one, it stays out of the queue until tomorrow.',
      tryThis: 'Use this as your “am I done triaging for today?” signal.',
      demoKind: AppHelpTourDemoKind.pulse,
    ),
  ],
);

final appHelpWorkspaceTour = AppHelpTourDefinition(
  id: AppHelpTourId.workspace,
  surface: AppHelpSurfaceId.workspace,
  title: 'Workspace walkthrough',
  description:
      'Workspace is the everyday planning surface. This walkthrough stays on the main board view and shows the controls you use most often.',
  steps: const [
    AppHelpTourStep(
      targetId: AppHelpTargetIds.workspaceCapture,
      title: 'Capture something quickly',
      description:
          'Capture is the fast entry point when you need to save a thought before deciding where it belongs.',
      tryThis:
          'Think of this as your front door for ideas, tasks, and loose reminders.',
      demoKind: AppHelpTourDemoKind.tap,
    ),
    AppHelpTourStep(
      targetId: AppHelpTargetIds.workspaceBoardScope,
      title: 'Choose which boards you are looking at',
      description:
          'Board scope decides whether you are planning inside one board or looking across several at once.',
      tryThis:
          'Use one board when you want focus, or more boards when you want a bigger picture.',
      demoKind: AppHelpTourDemoKind.tap,
    ),
    AppHelpTourStep(
      targetId: AppHelpTargetIds.workspaceViewPicker,
      title: 'Change the planning angle',
      description:
          'The view picker changes how the same work is laid out without making you leave the workspace.',
      tryThis:
          'Switch views when the current surface is making the work harder to understand.',
      demoKind: AppHelpTourDemoKind.tap,
    ),
    AppHelpTourStep(
      targetId: AppHelpTargetIds.workspaceFilters,
      title: 'Quiet the board down with filters',
      description:
          'Filters narrow the board so you can think about the right slice of work instead of everything at once.',
      tryThis:
          'Use filters when the board feels noisy or when you only want to look at one kind of work.',
      demoKind: AppHelpTourDemoKind.tap,
    ),
    AppHelpTourStep(
      targetId: AppHelpTargetIds.workspaceReminders,
      title: 'Review what needs attention',
      description:
          'Reminders pull overdue and upcoming work into one place so you can act without losing context.',
      tryThis:
          'This is the faster place to triage attention than hunting through the board manually.',
      demoKind: AppHelpTourDemoKind.pulse,
    ),
    AppHelpTourStep(
      targetId: AppHelpTargetIds.workspaceSearch,
      title: 'Jump straight to an item',
      description:
          'Search helps when you know roughly what you are looking for and do not want to navigate board by board.',
      tryThis:
          'Type part of a title and let the current workspace narrow in place.',
      demoKind: AppHelpTourDemoKind.tap,
    ),
    AppHelpTourStep(
      targetId: AppHelpTargetIds.workspaceKanbanSurface,
      title: 'Work directly on the board',
      description:
          'The main board surface is where planning turns into action: selecting items, moving them, and opening details.',
      tryThis:
          'This is where most day-to-day use happens once the top controls are set.',
      demoKind: AppHelpTourDemoKind.pulse,
    ),
  ],
);

final appHelpHierarchyTour = AppHelpTourDefinition(
  id: AppHelpTourId.hierarchy,
  surface: AppHelpSurfaceId.workspace,
  title: 'Hierarchy walkthrough',
  description:
      'Hierarchy is for understanding how goals, projects, tasks, and actions connect. This walkthrough puts the workspace into hierarchy mode first.',
  steps: const [
    AppHelpTourStep(
      targetId: AppHelpTargetIds.workspaceHierarchyControls,
      title: 'Steer the branch you are looking at',
      description:
          'These controls help you expand, collapse, and reset the branch you are exploring.',
      tryThis:
          'Use them whenever the tree gets too wide or when you want to recenter on one branch.',
      demoKind: AppHelpTourDemoKind.tap,
    ),
    AppHelpTourStep(
      targetId: AppHelpTargetIds.workspaceHierarchySurface,
      title: 'Read the work as a structure',
      description:
          'Hierarchy shows how smaller work rolls up into larger outcomes instead of only showing status columns.',
      tryThis:
          'Use hierarchy when you need to understand relationships before deciding what to do next.',
      demoKind: AppHelpTourDemoKind.pulse,
    ),
  ],
);

final appHelpInsightsTour = AppHelpTourDefinition(
  id: AppHelpTourId.insights,
  surface: AppHelpSurfaceId.insights,
  title: 'Insights walkthrough',
  description:
      'Insights is the reflection page. It helps you understand progress, friction, and momentum without turning the app into a corporate dashboard.',
  steps: const [
    AppHelpTourStep(
      targetId: AppHelpTargetIds.insightsHeader,
      title: 'Set the time window first',
      description:
          'The header controls the board and range you are reading, which changes the story the rest of the page tells.',
      tryThis:
          'Start with a shorter range for recent truth, then zoom out when you want a longer pattern.',
      demoKind: AppHelpTourDemoKind.tap,
    ),
    AppHelpTourStep(
      targetId: AppHelpTargetIds.insightsAccomplished,
      title: 'See what actually got done',
      description:
          'Accomplished is the grounded readout. It tells you what really finished instead of what merely moved.',
      tryThis: 'Use this first when you want an honest summary of output.',
      demoKind: AppHelpTourDemoKind.pulse,
    ),
    AppHelpTourStep(
      targetId: AppHelpTargetIds.insightsMomentum,
      title: 'Check whether progress is holding',
      description:
          'Momentum tells you whether work is continuing steadily or coming in bursts and stalls.',
      tryThis:
          'This is useful when your board feels inconsistent even if some items are getting done.',
      demoKind: AppHelpTourDemoKind.pulse,
    ),
    AppHelpTourStep(
      targetId: AppHelpTargetIds.insightsBoardHealth,
      title: 'Look for friction in the system',
      description:
          'Board health shows whether the board is being slowed by blockage, lateness, or stale work.',
      tryThis:
          'If the board feels heavy, this is usually the next place to look.',
      demoKind: AppHelpTourDemoKind.pulse,
    ),
    AppHelpTourStep(
      targetId: AppHelpTargetIds.insightsAttention,
      title: 'Catch early warning signs',
      description:
          'Attention signals highlight smaller problems before they become bigger drift.',
      tryThis:
          'Use this section for cleanup and early intervention, not just for reflection.',
      demoKind: AppHelpTourDemoKind.pulse,
    ),
  ],
);

final appHelpConfigurationTour = AppHelpTourDefinition(
  id: AppHelpTourId.configuration,
  surface: AppHelpSurfaceId.configuration,
  title: 'Configuration walkthrough',
  description:
      'Configuration is where you tune how the app behaves. This walkthrough shows the main sections so it feels less like a settings wall.',
  steps: const [
    AppHelpTourStep(
      targetId: AppHelpTargetIds.configurationBoardScope,
      title: 'Pick the board you are changing',
      description:
          'Configuration is board-aware, so start by making sure you are editing the right board.',
      tryThis:
          'Think of this section as choosing which workspace rules you are editing right now.',
      demoKind: AppHelpTourDemoKind.tap,
    ),
    AppHelpTourStep(
      targetId: AppHelpTargetIds.configurationBoardSettings,
      title: 'Tune how the board behaves',
      description:
          'Board settings control validation, reminders, defaults, theme, and other behavior-level choices.',
      tryThis:
          'Come here when the app should behave differently, not just look different.',
      demoKind: AppHelpTourDemoKind.pulse,
    ),
    AppHelpTourStep(
      targetId: AppHelpTargetIds.configurationColumns,
      title: 'Shape the statuses people move through',
      description:
          'Columns are the status language of the board, so changing them changes how planning works everywhere else.',
      tryThis:
          'Use this when the current statuses no longer match how you actually move work.',
      demoKind: AppHelpTourDemoKind.pulse,
    ),
    AppHelpTourStep(
      targetId: AppHelpTargetIds.configurationAccount,
      title: 'Manage the account on this device',
      description:
          'Account controls are for sign out, biometric unlock, and the intentional delete path.',
      tryThis:
          'This is the section for device/account management, not board configuration.',
      demoKind: AppHelpTourDemoKind.pulse,
    ),
    AppHelpTourStep(
      targetId: AppHelpTargetIds.configurationHelp,
      title: 'Replay tours whenever you need them',
      description:
          'The help section keeps guided walkthroughs and the floating help button within reach.',
      tryThis:
          'Come back here any time you want to re-run a walkthrough for yourself or someone else.',
      demoKind: AppHelpTourDemoKind.pulse,
    ),
  ],
);

final appHelpCalendarTour = AppHelpTourDefinition(
  id: AppHelpTourId.calendar,
  surface: AppHelpSurfaceId.workspace,
  title: 'Calendar walkthrough',
  description:
      'Calendar helps you see dated work clearly, then move things around without a heavy scheduling workflow. This walkthrough now changes the view as it goes.',
  steps: const [
    AppHelpTourStep(
      targetId: AppHelpTargetIds.calendarToolbar,
      title: 'Move through time',
      description:
          'Use Previous, Today, Next, and Month / Week / Day to control how you look at the schedule.',
      tryThis:
          'Watch the toolbar demo and remember that swiping left and right on the calendar does the same date movement.',
      demoKind: AppHelpTourDemoKind.swipeHorizontal,
    ),
    AppHelpTourStep(
      targetId: AppHelpTargetIds.calendarSurface,
      title: 'Read the calendar surface',
      description:
          'Month gives you a light overview, while Week and Day show a denser agenda view.',
      tryThis:
          'The walkthrough switches the calendar into a denser view here so you can see how the same work becomes more detailed.',
      demoKind: AppHelpTourDemoKind.tap,
    ),
    AppHelpTourStep(
      targetId: AppHelpTargetIds.calendarUnscheduledTray,
      title: 'Pull in work that has no date yet',
      description:
          'The Unscheduled tray keeps undated items close by without taking over the whole page.',
      tryThis:
          'Watch the tray open, then imagine either dragging an item onto the calendar or using Pick date as the simpler fallback.',
      demoKind: AppHelpTourDemoKind.slideUp,
    ),
  ],
);

final appHelpTours = <AppHelpTourId, AppHelpTourDefinition>{
  AppHelpTourId.workspace: appHelpWorkspaceTour,
  AppHelpTourId.hierarchy: appHelpHierarchyTour,
  AppHelpTourId.insights: appHelpInsightsTour,
  AppHelpTourId.configuration: appHelpConfigurationTour,
  AppHelpTourId.flow: appHelpFlowTour,
  AppHelpTourId.calendar: appHelpCalendarTour,
};
