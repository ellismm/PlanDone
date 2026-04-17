enum BoardCalendarSubview {
  month,
  week,
  day,
}

enum BoardCalendarMarkerKind {
  start,
  targetEnd,
  due,
}

class BoardCalendarPreferences {
  const BoardCalendarPreferences({
    this.lastSubview = BoardCalendarSubview.month,
    this.visibleDateKinds = const <BoardCalendarMarkerKind>{
      BoardCalendarMarkerKind.start,
      BoardCalendarMarkerKind.targetEnd,
      BoardCalendarMarkerKind.due,
    },
    this.showUnscheduled = true,
  });

  final BoardCalendarSubview lastSubview;
  final Set<BoardCalendarMarkerKind> visibleDateKinds;
  final bool showUnscheduled;

  BoardCalendarPreferences copyWith({
    BoardCalendarSubview? lastSubview,
    Set<BoardCalendarMarkerKind>? visibleDateKinds,
    bool? showUnscheduled,
  }) {
    return BoardCalendarPreferences(
      lastSubview: lastSubview ?? this.lastSubview,
      visibleDateKinds: visibleDateKinds ?? this.visibleDateKinds,
      showUnscheduled: showUnscheduled ?? this.showUnscheduled,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'lastSubview': lastSubview.name,
      'visibleDateKinds': visibleDateKinds.map((kind) => kind.name).toList(),
      'showUnscheduled': showUnscheduled,
    };
  }

  static BoardCalendarPreferences fromMap(Map<String, Object?>? map) {
    if (map == null) return const BoardCalendarPreferences();

    final subview = BoardCalendarSubview.values.firstWhere(
      (entry) => entry.name == map['lastSubview'],
      orElse: () => BoardCalendarSubview.month,
    );

    final rawKinds = (map['visibleDateKinds'] as List?)
            ?.whereType<String>()
            .map(
              (name) => BoardCalendarMarkerKind.values.where(
                (entry) => entry.name == name,
              ),
            )
            .where((matches) => matches.isNotEmpty)
            .map((matches) => matches.first)
            .toSet() ??
        const <BoardCalendarMarkerKind>{
          BoardCalendarMarkerKind.start,
          BoardCalendarMarkerKind.targetEnd,
          BoardCalendarMarkerKind.due,
        };

    return BoardCalendarPreferences(
      lastSubview: subview,
      visibleDateKinds: rawKinds.isEmpty
          ? const <BoardCalendarMarkerKind>{
              BoardCalendarMarkerKind.start,
              BoardCalendarMarkerKind.targetEnd,
              BoardCalendarMarkerKind.due,
            }
          : rawKinds,
      showUnscheduled: map['showUnscheduled'] != false,
    );
  }
}
