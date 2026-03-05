import 'dart:math' as math;

import '../outbox/outbox_queue.dart';
import 'sync_remote_adapter.dart';

class SyncRunReport {
  const SyncRunReport({
    required this.processed,
    required this.failed,
    required this.failedOperationIds,
    this.permissionDenied = 0,
    this.permissionDeniedOperationIds = const <String>[],
  });

  final int processed;
  final int failed;
  final List<String> failedOperationIds;
  final int permissionDenied;
  final List<String> permissionDeniedOperationIds;
}

class SyncEngine {
  SyncEngine({
    required OutboxQueue outboxQueue,
    required SyncRemoteAdapter remoteAdapter,
    this.baseRetryDelay = const Duration(seconds: 5),
    this.maxRetryDelay = const Duration(minutes: 5),
  })  : _outboxQueue = outboxQueue,
        _remoteAdapter = remoteAdapter;

  final OutboxQueue _outboxQueue;
  final SyncRemoteAdapter _remoteAdapter;
  final Duration baseRetryDelay;
  final Duration maxRetryDelay;

  Future<SyncRunReport> syncPending({bool ignoreRetrySchedule = false}) async {
    final pending = await _outboxQueue.listPending();
    var processed = 0;
    final failedIds = <String>[];
    final permissionDeniedIds = <String>[];

    for (final op in pending) {
      final now = DateTime.now();
      final nextAttemptAt = op.nextAttemptAt;
      if (!ignoreRetrySchedule &&
          nextAttemptAt != null &&
          nextAttemptAt.isAfter(now)) {
        continue;
      }

      try {
        await _remoteAdapter.applyOperation(op);
        await _outboxQueue.markProcessed(op.id);
        processed += 1;
      } on SyncRemotePermissionDeniedException {
        // Role/membership may have changed while offline; do not retry forever.
        permissionDeniedIds.add(op.id);
        await _outboxQueue.markProcessed(op.id);
      } catch (error) {
        failedIds.add(op.id);

        final nextAttemptCount = op.attemptCount + 1;
        final exponent = math.max(0, nextAttemptCount - 1);
        final factor = 1 << exponent;
        final rawDelaySeconds = baseRetryDelay.inSeconds * factor;
        final boundedDelaySeconds =
            math.min(rawDelaySeconds, maxRetryDelay.inSeconds);
        final retryAt = now.add(Duration(seconds: boundedDelaySeconds));

        await _outboxQueue.update(
          op.copyWith(
            attemptCount: nextAttemptCount,
            lastError: error.toString(),
            nextAttemptAt: retryAt,
            lastAttemptAt: now,
          ),
        );
      }
    }

    return SyncRunReport(
      processed: processed,
      failed: failedIds.length,
      failedOperationIds: failedIds,
      permissionDenied: permissionDeniedIds.length,
      permissionDeniedOperationIds: permissionDeniedIds,
    );
  }
}
