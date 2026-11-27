import '../data/attendance_database.dart';
import '../data/attendance_summary.dart';
import '../data/checkin_record.dart';
import '../data/wecom_exception.dart';
import 'wecom_api_client.dart';

class AttendanceSyncService {
  AttendanceSyncService({
    required this.apiClient,
    required this.database,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final WeComApiClient apiClient;
  final AttendanceDatabase database;
  final DateTime Function() _clock;

  Future<AttendanceSyncResult> syncAll({
    required DateTime firstMonth,
    required DateTime lastMonth,
    required Iterable<String> userIds,
    DateTime? startAt,
    AttendanceSyncMode mode = AttendanceSyncMode.full,
    void Function(AttendanceSyncProgress progress)? onProgress,
  }) async {
    final uniqueUserIds =
        userIds
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    if (uniqueUserIds.isEmpty) {
      throw const WeComException('没有可同步的成员');
    }

    final windows = buildAttendanceSyncWindows(
      firstMonth,
      lastMonth,
      startAt: startAt,
    );
    final userBatches = <List<String>>[
      for (var index = 0; index < uniqueUserIds.length; index += 100)
        uniqueUserIds.sublist(
          index,
          (index + 100).clamp(0, uniqueUserIds.length),
        ),
    ];
    final existingSnapshotKeys = mode == AttendanceSyncMode.incremental
        ? await database.loadSyncedWindowKeys(
            firstMonth: firstMonth,
            lastMonth: lastMonth,
            userIds: uniqueUserIds.toSet(),
          )
        : const <String>{};
    final now = _clock();
    final latestCompletedWindowStart = windows
        .where((window) => !window.endExclusive.isAfter(now))
        .map((window) => window.start)
        .fold<DateTime?>(
          null,
          (latest, start) =>
              latest == null || start.isAfter(latest) ? start : latest,
        );
    final tasks = <_SyncTask>[];
    for (final window in windows) {
      final isCurrentWindow =
          !now.isBefore(window.start) && now.isBefore(window.endExclusive);
      final isLatestCompletedWindow =
          latestCompletedWindowStart != null &&
          window.start.isAtSameMomentAs(latestCompletedWindowStart);
      for (var batchIndex = 0; batchIndex < userBatches.length; batchIndex++) {
        final batch = userBatches[batchIndex]
            .where(
              (userId) =>
                  mode == AttendanceSyncMode.full ||
                  isCurrentWindow ||
                  isLatestCompletedWindow ||
                  !existingSnapshotKeys.contains(
                    '${window.start.millisecondsSinceEpoch}|$userId',
                  ),
            )
            .toList(growable: false);
        if (batch.isNotEmpty) {
          tasks.add(
            _SyncTask(window: window, batch: batch, batchIndex: batchIndex),
          );
        }
      }
    }
    final totalSteps = tasks.length;
    final syncRunId = await database.startSyncRun(
      firstMonth: firstMonth,
      lastMonth: lastMonth,
      userCount: uniqueUserIds.length,
      mode: mode,
    );
    var recordCount = 0;
    var step = 0;

    try {
      for (final task in tasks) {
        final window = task.window;
        final batch = task.batch;
        step++;
        onProgress?.call(
          AttendanceSyncProgress(
            completedSteps: step - 1,
            totalSteps: totalSteps,
            window: window,
            memberBatch: task.batchIndex + 1,
            memberBatchCount: userBatches.length,
            recordCount: recordCount,
            phase: '正在拉取打卡明细',
          ),
        );

        final records = await apiClient.getCheckinData(
          dataType: CheckinDataType.all,
          start: window.start,
          end: window.endInclusive,
          userIds: batch,
        );
        recordCount += mode == AttendanceSyncMode.full
            ? await database.replaceCheckinRecords(
                records,
                periodStart: window.start,
                periodEndExclusive: window.endExclusive,
                userIds: batch,
              )
            : await database.saveCheckinRecords(records);
        onProgress?.call(
          AttendanceSyncProgress(
            completedSteps: step - 1,
            totalSteps: totalSteps,
            window: window,
            memberBatch: task.batchIndex + 1,
            memberBatchCount: userBatches.length,
            recordCount: recordCount,
            phase: '已整批写入 ${records.length} 条，继续获取',
          ),
        );
        await database.markSyncWindows(
          periodStart: window.start,
          periodEndExclusive: window.endExclusive,
          userIds: batch,
        );
        onProgress?.call(
          AttendanceSyncProgress(
            completedSteps: step,
            totalSteps: totalSteps,
            window: window,
            memberBatch: task.batchIndex + 1,
            memberBatchCount: userBatches.length,
            recordCount: recordCount,
            phase: '本周期同步完成',
          ),
        );
      }

      await database.finishSyncRun(
        syncRunId,
        succeeded: true,
        recordCount: recordCount,
        reportCount: 0,
      );
      return AttendanceSyncResult(
        checkinRecordCount: recordCount,
        userCount: uniqueUserIds.length,
        windowCount: tasks.map((task) => task.window).toSet().length,
      );
    } catch (error) {
      await database.finishSyncRun(
        syncRunId,
        succeeded: false,
        recordCount: recordCount,
        reportCount: 0,
        errorMessage: error.toString(),
      );
      rethrow;
    }
  }
}

class _SyncTask {
  const _SyncTask({
    required this.window,
    required this.batch,
    required this.batchIndex,
  });

  final AttendanceSyncWindow window;
  final List<String> batch;
  final int batchIndex;
}

class AttendanceSyncProgress {
  const AttendanceSyncProgress({
    required this.completedSteps,
    required this.totalSteps,
    required this.window,
    required this.memberBatch,
    required this.memberBatchCount,
    required this.recordCount,
    required this.phase,
  });

  final int completedSteps;
  final int totalSteps;
  final AttendanceSyncWindow window;
  final int memberBatch;
  final int memberBatchCount;
  final int recordCount;
  final String phase;

  String get message {
    final batchText = memberBatchCount > 1
        ? '，成员批次 $memberBatch/$memberBatchCount'
        : '';
    return '$phase $completedSteps/$totalSteps\n'
        '${window.label}$batchText\n'
        '已写入 $recordCount 条每日原始打卡记录';
  }
}

class AttendanceSyncResult {
  const AttendanceSyncResult({
    required this.checkinRecordCount,
    required this.userCount,
    required this.windowCount,
  });

  final int checkinRecordCount;
  final int userCount;
  final int windowCount;
}
