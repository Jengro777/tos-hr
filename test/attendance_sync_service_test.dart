import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tospino_hr/config/wecom_config.dart';
import 'package:tospino_hr/data/attendance_database.dart';
import 'package:tospino_hr/data/attendance_summary.dart';
import 'package:tospino_hr/data/checkin_record.dart';
import 'package:tospino_hr/data/monthly_report.dart';
import 'package:tospino_hr/services/attendance_sync_service.dart';
import 'package:tospino_hr/services/wecom_api_client.dart';

void main() {
  test('syncs half-month check-ins and natural-month reports', () async {
    var checkinCalls = 0;
    var monthlyReportCalls = 0;
    final mockClient = MockClient((request) async {
      if (request.url.path == '/cgi-bin/gettoken') {
        return _jsonResponse({
          'errcode': 0,
          'access_token': 'token',
          'expires_in': 7200,
        });
      }
      if (request.url.path == '/cgi-bin/checkin/getcheckindata') {
        checkinCalls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final start = body['starttime'] as int;
        return _jsonResponse({
          'errcode': 0,
          'checkindata': [
            {
              'userid': 'PM07',
              'groupname': 'Tospino打卡',
              'checkin_type': '上班打卡',
              'checkin_time': start + 9 * 3600,
            },
          ],
        });
      }
      if (request.url.path == '/cgi-bin/checkin/getcheckin_monthdata') {
        monthlyReportCalls++;
        return _jsonResponse({
          'errcode': 0,
          'datas': [
            {
              'base_info': {
                'name': '吴振国',
                'acctid': 'PM07',
                'rule_info': {'groupid': 10, 'groupname': 'Tospino打卡'},
              },
              'summary_info': {
                'work_days': 20,
                'regular_days': 19,
                'rest_days': 10,
                'except_days': 1,
                'regular_work_sec': 518400,
                'standard_work_sec': 576000,
              },
              'exception_infos': const [],
              'sp_items': const [],
            },
          ],
        });
      }
      fail('Unexpected request: ${request.url}');
    });
    final apiClient = WeComApiClient(
      config: const WecomConfig(
        corpId: 'ww-test',
        agentId: '1000012',
        secret: 'secret',
      ),
      httpClient: mockClient,
    );
    addTearDown(apiClient.close);
    final database = _MemoryAttendanceDatabase();
    addTearDown(database.close);
    final service = AttendanceSyncService(
      apiClient: apiClient,
      database: database,
      clock: () => DateTime(2026, 11, 27),
    );

    final result = await service.syncAll(
      firstMonth: DateTime(2026, 11),
      lastMonth: DateTime(2026, 11),
      userIds: const ['PM07'],
    );
    final stats = await database.loadStats();

    expect(checkinCalls, 2);
    expect(monthlyReportCalls, 1);
    expect(result.checkinRecordCount, 2);
    expect(result.reportCount, 1);
    expect(stats.checkinRecordCount, 2);
    expect(stats.monthlyReportCount, 1);
    expect(stats.lastRun?.status, 'completed');
    expect(stats.lastRun?.syncMode, 'full');
    expect(stats.lastRun?.reportCount, 1);

    final incremental = await service.syncAll(
      firstMonth: DateTime(2026, 11),
      lastMonth: DateTime(2026, 11),
      userIds: const ['PM07'],
      startAt: DateTime(2026, 11, 16),
      mode: AttendanceSyncMode.incremental,
    );
    final incrementalStats = await database.loadStats();

    expect(checkinCalls, 3);
    expect(monthlyReportCalls, 2);
    expect(incremental.windowCount, 2);
    expect(incremental.reportCount, 1);
    expect(incrementalStats.checkinRecordCount, 2);
    expect(incrementalStats.monthlyReportCount, 1);
    expect(incrementalStats.lastRun?.syncMode, 'incremental');

    final reportOnly = await service.syncAll(
      firstMonth: DateTime(2026, 11),
      lastMonth: DateTime(2026, 11),
      userIds: const ['PM07'],
      startAt: DateTime(2026, 11, 16),
      mode: AttendanceSyncMode.incremental,
      dataset: AttendanceSyncDataset.reports,
    );
    expect(checkinCalls, 3);
    expect(monthlyReportCalls, 3);
    expect(reportOnly.checkinRecordCount, 0);
    expect(reportOnly.reportCount, 1);

    final checkinOnly = await service.syncAll(
      firstMonth: DateTime(2026, 11),
      lastMonth: DateTime(2026, 11),
      userIds: const ['PM07'],
      startAt: DateTime(2026, 11, 16),
      mode: AttendanceSyncMode.incremental,
      dataset: AttendanceSyncDataset.checkins,
    );
    expect(checkinCalls, 4);
    expect(monthlyReportCalls, 3);
    expect(checkinOnly.checkinRecordCount, 1);
    expect(checkinOnly.reportCount, 0);

    final monthlyRows = await database.loadMonthlySummary(
      firstMonth: DateTime(2026, 11),
      lastMonth: DateTime(2026, 11),
    );
    expect(monthlyRows.single.valueOf(AttendanceMetric.expectedDays), 20);
    expect(
      monthlyRows.single.valueOf(AttendanceMetric.normalAttendanceDays),
      19,
    );
    expect(monthlyRows.single.valueOf(AttendanceMetric.attendanceDays), 2);
  });
}

class _MemoryAttendanceDatabase extends AttendanceDatabase {
  final Map<String, CheckinRecord> _records = {};
  final Map<String, _StoredReport> _reports = {};
  final Set<String> _syncedWindows = {};
  AttendanceSyncRun? _lastRun;
  int _runSequence = 0;

  @override
  Future<int> saveCheckinRecords(Iterable<CheckinRecord> records) async {
    for (final record in records) {
      _records[record.sourceKey] = record;
    }
    return records.length;
  }

  @override
  Future<int> replaceCheckinRecords(
    Iterable<CheckinRecord> records, {
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    required Iterable<String> userIds,
  }) async {
    final ids = userIds.toSet();
    _records.removeWhere(
      (_, record) =>
          ids.contains(record.userId) &&
          !record.checkinTime.isBefore(periodStart) &&
          record.checkinTime.isBefore(periodEndExclusive),
    );
    return saveCheckinRecords(records);
  }

  @override
  Future<int> replaceMonthlyReports(
    Iterable<MonthlyReport> reports, {
    required int year,
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    required Iterable<String> userIds,
  }) async {
    final ids = userIds.toSet();
    _reports.removeWhere(
      (_, stored) =>
          ids.contains(stored.userId) &&
          stored.periodStart.isAtSameMomentAs(periodStart),
    );
    var count = 0;
    for (final report in reports) {
      _reports['${periodStart.millisecondsSinceEpoch}|${report.userId}'] =
          _StoredReport(year: year, periodStart: periodStart, report: report);
      count++;
    }
    return count;
  }

  @override
  Future<Set<String>> loadSyncedWindowKeys({
    required DateTime firstMonth,
    required DateTime lastMonth,
    required Set<String> userIds,
  }) async {
    return _filterWindowKeys(_syncedWindows, userIds);
  }

  @override
  Future<Set<String>> loadSyncedSnapshotKeys({
    required DateTime firstMonth,
    required DateTime lastMonth,
    required Set<String> userIds,
  }) async {
    return _filterWindowKeys({
      for (final stored in _reports.values)
        '${stored.periodStart.millisecondsSinceEpoch}|${stored.userId}',
    }, userIds);
  }

  Set<String> _filterWindowKeys(Set<String> keys, Set<String> userIds) {
    return {
      for (final key in keys)
        if (userIds.isEmpty || userIds.contains(key.split('|').last)) key,
    };
  }

  @override
  Future<void> markSyncWindows({
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    required Iterable<String> userIds,
  }) async {
    for (final userId in userIds) {
      _syncedWindows.add('${periodStart.millisecondsSinceEpoch}|$userId');
    }
  }

  @override
  Future<int> startSyncRun({
    required DateTime firstMonth,
    required DateTime lastMonth,
    required int userCount,
    required AttendanceSyncMode mode,
  }) async {
    _runSequence++;
    _lastRun = AttendanceSyncRun(
      id: _runSequence,
      startedAt: DateTime.now(),
      firstMonth: _monthKey(firstMonth),
      lastMonth: _monthKey(lastMonth),
      userCount: userCount,
      syncMode: mode.name,
      status: 'running',
      recordCount: 0,
      reportCount: 0,
    );
    return _runSequence;
  }

  @override
  Future<void> finishSyncRun(
    int id, {
    required bool succeeded,
    required int recordCount,
    required int reportCount,
    String? errorMessage,
  }) async {
    final previous = _lastRun;
    if (previous == null) {
      return;
    }
    _lastRun = AttendanceSyncRun(
      id: id,
      startedAt: previous.startedAt,
      completedAt: DateTime.now(),
      firstMonth: previous.firstMonth,
      lastMonth: previous.lastMonth,
      userCount: previous.userCount,
      syncMode: previous.syncMode,
      status: succeeded ? 'completed' : 'failed',
      recordCount: recordCount,
      reportCount: reportCount,
      errorMessage: errorMessage,
    );
  }

  @override
  Future<AttendanceDatabaseStats> loadStats() async {
    return AttendanceDatabaseStats(
      checkinRecordCount: _records.length,
      monthlyReportCount: _reports.length,
      lastRun: _lastRun,
    );
  }

  @override
  Future<List<AttendanceSummaryRow>> loadMonthlySummary({
    required DateTime firstMonth,
    required DateTime lastMonth,
    Set<String> userIds = const {},
  }) async {
    final builder = AttendanceMonthlySummaryBuilder();
    for (final stored in _reports.values) {
      if (userIds.isNotEmpty && !userIds.contains(stored.userId)) {
        continue;
      }
      builder.addReports(
        [stored.report],
        year: stored.periodStart.year,
        month: stored.periodStart.month,
      );
    }
    return [
      for (final row in builder.build())
        row
            .withMetric(
              AttendanceMetric.checkinRecordCount,
              _records.values
                  .where((record) => record.userId == row.userId)
                  .length
                  .toDouble(),
            )
            .withMetric(
              AttendanceMetric.attendanceDays,
              _records.values
                  .where(
                    (record) =>
                        record.userId == row.userId &&
                        !record.exceptionType.contains('未打卡') &&
                        const {'上班打卡', '下班打卡'}.contains(record.checkinType),
                  )
                  .map(
                    (record) =>
                        '${record.checkinTime.year}-${record.checkinTime.month}-'
                        '${record.checkinTime.day}',
                  )
                  .toSet()
                  .length
                  .toDouble(),
            ),
    ];
  }
}

class _StoredReport {
  const _StoredReport({
    required this.year,
    required this.periodStart,
    required this.report,
  });

  final int year;
  final DateTime periodStart;
  final MonthlyReport report;

  String get userId => report.userId;
}

String _monthKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}';

http.Response _jsonResponse(Map<String, Object?> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}
