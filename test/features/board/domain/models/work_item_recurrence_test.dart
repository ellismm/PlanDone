import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/features/board/domain/models/work_item_recurrence.dart';

void main() {
  test('recurrence map round-trip preserves values', () {
    final recurrence = WorkItemRecurrence(
      enabled: true,
      cadence: WorkItemRecurrenceCadence.customDays,
      interval: 3,
      completionGated: true,
      rootItemId: 'item-1',
      sequence: 2,
    );

    final restored = WorkItemRecurrence.fromMap(recurrence.toMap());

    expect(restored, isNotNull);
    expect(restored!.enabled, isTrue);
    expect(restored.cadence, WorkItemRecurrenceCadence.customDays);
    expect(restored.interval, 3);
    expect(restored.intervalDays, 3);
    expect(restored.completionGated, isTrue);
    expect(restored.rootItemId, 'item-1');
    expect(restored.sequence, 2);
  });

  test('weekly cadence converts interval to 7-day increments', () {
    final recurrence = WorkItemRecurrence(
      cadence: WorkItemRecurrenceCadence.weekly,
      interval: 2,
      rootItemId: 'root',
    );
    expect(recurrence.intervalDays, 14);
  });
}
