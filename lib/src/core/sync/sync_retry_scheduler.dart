import 'dart:async';

typedef SyncRetryClock = DateTime Function();
typedef SyncRetryTimerFactory = Timer Function(
  Duration delay,
  void Function() callback,
);

/// Keeps one timer aligned with the earliest retry time in the sync outbox.
///
/// The owner remains responsible for recalculating the next retry time after
/// each sync attempt. Scheduling a new value replaces any existing timer.
class SyncRetryScheduler {
  SyncRetryScheduler({
    required Future<void> Function() onRetry,
    SyncRetryClock? clock,
    SyncRetryTimerFactory? timerFactory,
  })  : _onRetry = onRetry,
        _clock = clock ?? DateTime.now,
        _timerFactory = timerFactory ?? Timer.new;

  final Future<void> Function() _onRetry;
  final SyncRetryClock _clock;
  final SyncRetryTimerFactory _timerFactory;

  Timer? _timer;
  DateTime? _scheduledRetryAt;
  bool _disposed = false;

  DateTime? get scheduledRetryAt => _scheduledRetryAt;

  void schedule(DateTime? retryAt) {
    if (_disposed) return;
    if (retryAt == null) {
      cancel();
      return;
    }
    if (_timer?.isActive == true && _scheduledRetryAt == retryAt) {
      return;
    }

    cancel();
    final remaining = retryAt.difference(_clock());
    final delay = remaining.isNegative ? Duration.zero : remaining;
    _scheduledRetryAt = retryAt;
    _timer = _timerFactory(delay, () {
      _timer = null;
      _scheduledRetryAt = null;
      unawaited(_runRetry());
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _scheduledRetryAt = null;
  }

  void dispose() {
    _disposed = true;
    cancel();
  }

  Future<void> _runRetry() async {
    try {
      await _onRetry();
    } catch (_) {
      // Automatic retry is best-effort. The sync state/outbox retains the
      // operation and exposes the error while the owner schedules the next run.
    }
  }
}
