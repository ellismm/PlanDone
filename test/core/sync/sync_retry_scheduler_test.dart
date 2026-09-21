import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/core/sync/sync_retry_scheduler.dart';

class _FakeTimer implements Timer {
  _FakeTimer(this.callback);

  final void Function() callback;
  bool _isActive = true;
  int _tick = 0;

  @override
  bool get isActive => _isActive;

  @override
  int get tick => _tick;

  @override
  void cancel() {
    _isActive = false;
  }

  void fire() {
    if (!_isActive) return;
    _isActive = false;
    _tick += 1;
    callback();
  }
}

void main() {
  test('schedules one retry for the requested backoff time', () async {
    final now = DateTime(2026, 8, 25, 10);
    final delays = <Duration>[];
    final timers = <_FakeTimer>[];
    var retryCount = 0;
    final scheduler = SyncRetryScheduler(
      onRetry: () async {
        retryCount += 1;
      },
      clock: () => now,
      timerFactory: (delay, callback) {
        delays.add(delay);
        final timer = _FakeTimer(callback);
        timers.add(timer);
        return timer;
      },
    );
    addTearDown(scheduler.dispose);

    final retryAt = now.add(const Duration(seconds: 5));
    scheduler.schedule(retryAt);
    scheduler.schedule(retryAt);

    expect(delays, [const Duration(seconds: 5)]);
    expect(scheduler.scheduledRetryAt, retryAt);

    timers.single.fire();
    await Future<void>.delayed(Duration.zero);

    expect(retryCount, 1);
    expect(scheduler.scheduledRetryAt, isNull);
  });

  test('replaces a later retry and cancels when no retry remains', () {
    final now = DateTime(2026, 8, 25, 10);
    final delays = <Duration>[];
    final timers = <_FakeTimer>[];
    final scheduler = SyncRetryScheduler(
      onRetry: () async {},
      clock: () => now,
      timerFactory: (delay, callback) {
        delays.add(delay);
        final timer = _FakeTimer(callback);
        timers.add(timer);
        return timer;
      },
    );
    addTearDown(scheduler.dispose);

    scheduler.schedule(now.add(const Duration(minutes: 2)));
    scheduler.schedule(now.add(const Duration(seconds: 30)));

    expect(delays, [
      const Duration(minutes: 2),
      const Duration(seconds: 30),
    ]);
    expect(timers.first.isActive, isFalse);
    expect(timers.last.isActive, isTrue);

    scheduler.schedule(null);

    expect(timers.last.isActive, isFalse);
    expect(scheduler.scheduledRetryAt, isNull);
  });

  test('runs an already-due retry without a negative timer duration', () {
    final now = DateTime(2026, 8, 25, 10);
    Duration? scheduledDelay;
    final scheduler = SyncRetryScheduler(
      onRetry: () async {},
      clock: () => now,
      timerFactory: (delay, callback) {
        scheduledDelay = delay;
        return _FakeTimer(callback);
      },
    );
    addTearDown(scheduler.dispose);

    scheduler.schedule(now.subtract(const Duration(seconds: 1)));

    expect(scheduledDelay, Duration.zero);
  });
}
