class NotificationPreferences {
  const NotificationPreferences({
    this.enabled = true,
    this.remindOnStartDate = false,
    this.remindOnDueDate = true,
    this.startReminderMinutesBefore = 15,
    this.dueReminderMinutesBefore = 60,
    this.defaultSnoozeMinutes = 60,
    this.mutedUntil,
    this.snoozedReminderUntilEpochMillis = const <String, int>{},
  });

  final bool enabled;
  final bool remindOnStartDate;
  final bool remindOnDueDate;
  final int startReminderMinutesBefore;
  final int dueReminderMinutesBefore;
  final int defaultSnoozeMinutes;
  final DateTime? mutedUntil;
  final Map<String, int> snoozedReminderUntilEpochMillis;

  bool get isMutedNow {
    final until = mutedUntil;
    if (until == null) return false;
    return until.isAfter(DateTime.now());
  }

  NotificationPreferences copyWith({
    bool? enabled,
    bool? remindOnStartDate,
    bool? remindOnDueDate,
    int? startReminderMinutesBefore,
    int? dueReminderMinutesBefore,
    int? defaultSnoozeMinutes,
    DateTime? mutedUntil,
    bool clearMutedUntil = false,
    Map<String, int>? snoozedReminderUntilEpochMillis,
  }) {
    return NotificationPreferences(
      enabled: enabled ?? this.enabled,
      remindOnStartDate: remindOnStartDate ?? this.remindOnStartDate,
      remindOnDueDate: remindOnDueDate ?? this.remindOnDueDate,
      startReminderMinutesBefore:
          startReminderMinutesBefore ?? this.startReminderMinutesBefore,
      dueReminderMinutesBefore:
          dueReminderMinutesBefore ?? this.dueReminderMinutesBefore,
      defaultSnoozeMinutes: defaultSnoozeMinutes ?? this.defaultSnoozeMinutes,
      mutedUntil: clearMutedUntil ? null : (mutedUntil ?? this.mutedUntil),
      snoozedReminderUntilEpochMillis: snoozedReminderUntilEpochMillis ??
          Map<String, int>.from(this.snoozedReminderUntilEpochMillis),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'enabled': enabled,
      'remindOnStartDate': remindOnStartDate,
      'remindOnDueDate': remindOnDueDate,
      'startReminderMinutesBefore': startReminderMinutesBefore,
      'dueReminderMinutesBefore': dueReminderMinutesBefore,
      'defaultSnoozeMinutes': defaultSnoozeMinutes,
      'mutedUntil': mutedUntil?.millisecondsSinceEpoch,
      'snoozedReminderUntilEpochMillis': snoozedReminderUntilEpochMillis,
    };
  }

  static NotificationPreferences fromMap(Map<String, Object?>? map) {
    if (map == null) return const NotificationPreferences();

    bool readBool(String key, bool fallback) {
      final value = map[key];
      if (value is bool) return value;
      return fallback;
    }

    int readInt(String key, int fallback) {
      final value = map[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) return parsed;
      }
      return fallback;
    }

    DateTime? readDateTime(String key) {
      final value = map[key];
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is num) {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      }
      if (value is String) {
        final asInt = int.tryParse(value);
        if (asInt != null) return DateTime.fromMillisecondsSinceEpoch(asInt);
      }
      return null;
    }

    Map<String, int> readSnoozedMap(String key) {
      final value = map[key];
      if (value is! Map) return const <String, int>{};
      final next = <String, int>{};
      for (final entry in value.entries) {
        final reminderId = entry.key.toString().trim();
        if (reminderId.isEmpty) continue;
        final rawUntil = entry.value;
        if (rawUntil is int) {
          next[reminderId] = rawUntil;
          continue;
        }
        if (rawUntil is num) {
          next[reminderId] = rawUntil.toInt();
          continue;
        }
        if (rawUntil is String) {
          final parsed = int.tryParse(rawUntil);
          if (parsed != null) next[reminderId] = parsed;
        }
      }
      return next;
    }

    return NotificationPreferences(
      enabled: readBool('enabled', true),
      remindOnStartDate: readBool('remindOnStartDate', false),
      remindOnDueDate: readBool('remindOnDueDate', true),
      startReminderMinutesBefore:
          readInt('startReminderMinutesBefore', 15).clamp(0, 7 * 24 * 60),
      dueReminderMinutesBefore:
          readInt('dueReminderMinutesBefore', 60).clamp(0, 7 * 24 * 60),
      defaultSnoozeMinutes:
          readInt('defaultSnoozeMinutes', 60).clamp(5, 7 * 24 * 60),
      mutedUntil: readDateTime('mutedUntil'),
      snoozedReminderUntilEpochMillis:
          readSnoozedMap('snoozedReminderUntilEpochMillis'),
    );
  }
}
