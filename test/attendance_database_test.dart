import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tospino_hr/data/attendance_database.dart';
import 'package:tospino_hr/data/attendance_summary.dart';
import 'package:tospino_hr/data/checkin_record.dart';
import 'package:tospino_hr/data/monthly_report.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('stores check-in records and merges cached monthly reports', () async {
    final database = AttendanceDatabase(
      factory: databaseFactoryFfiNoIsolate,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(database.close);

    await database.saveCheckinRecords([
      CheckinRecord(
        userId: 'PM07',
        checkinType: '上班打卡',
        checkinTime: DateTime(2026, 11, 2, 9),
      ),
      CheckinRecord(
        userId: 'PM07',
        checkinType: '下班打卡',
        checkinTime: DateTime(2026, 11, 2, 18),
      ),
      CheckinRecord(
        userId: 'PM07',
        checkinType: '外出打卡',
        exceptionType: '时间异常',
        checkinTime: DateTime(2026, 11, 3, 10),
      ),
    ]);
    await database.saveMonthlyReports(
      [_report(workDays: 10, exceptionDays: 1, lateCount: 1)],
      year: 2026,
      periodStart: DateTime(2026, 11, 1),
      periodEndExclusive: DateTime(2026, 11, 16),
    );
    await database.saveMonthlyReports(
      [_report(workDays: 9, exceptionDays: 2, lateCount: 2)],
      year: 2026,
      periodStart: DateTime(2026, 11, 16),
      periodEndExclusive: DateTime(2026, 12, 1),
    );

    final stats = await database.loadStats();
    final rows = await database.loadSummary(
      firstYear: 2026,
      lastYear: 2026,
      userIds: {'PM07'},
    );
    final monthlyRows = await database.loadMonthlySummary(
      firstMonth: DateTime(2026, 11),
      lastMonth: DateTime(2026, 11),
      userIds: {'PM07'},
    );
    final allTimeRows = await database.loadAllTimeSummary(
      firstMonth: DateTime(2026, 11),
      lastMonth: DateTime(2026, 11),
      userIds: {'PM07'},
    );
    final dailyRows = await database.loadDailyCheckinSummary(
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 30),
      userIds: {'PM07'},
    );
    final bounds = await database.loadCheckinDateBounds();
    final recordPage = await database.loadCheckinRecords(
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 30),
      userIds: const {'PM07'},
      dataType: CheckinDataType.all,
    );
    final rawYearRows = await database.loadRawYearSummary(
      firstYear: 2026,
      lastYear: 2026,
    );
    final rawMonthlyRows = await database.loadRawMonthlySummary(
      firstMonth: DateTime(2026, 11),
      lastMonth: DateTime(2026, 11),
    );

    expect(stats.checkinRecordCount, 3);
    expect(stats.monthlyReportCount, 2);
    expect(rows.single.sourceRecordCount, 2);
    expect(rows.single.valueOf(AttendanceMetric.expectedDays), 19);
    expect(rows.single.valueOf(AttendanceMetric.exceptionDays), 3);
    expect(rows.single.valueOf(AttendanceMetric.lateCount), 3);
    expect(rows.single.valueOf(AttendanceMetric.checkinRecordCount), 3);
    expect(monthlyRows.single.periodLabel, '2026-11');
    expect(monthlyRows.single.sourceRecordCount, 2);
    expect(monthlyRows.single.valueOf(AttendanceMetric.lateCount), 3);
    expect(monthlyRows.single.valueOf(AttendanceMetric.checkinRecordCount), 3);
    expect(allTimeRows.single.periodLabel, '全部历史');
    expect(allTimeRows.single.valueOf(AttendanceMetric.expectedDays), 19);
    expect(allTimeRows.single.valueOf(AttendanceMetric.checkinRecordCount), 3);
    expect(dailyRows.single.valueOf(AttendanceMetric.checkinRecordCount), 3);
    expect(dailyRows.single.valueOf(AttendanceMetric.attendanceDays), 1);
    expect(bounds?.firstDate, DateTime(2026, 11, 2));
    expect(bounds?.lastDate, DateTime(2026, 11, 3));
    expect(recordPage.totalCount, 3);
    expect(recordPage.totalUserCount, 1);
    expect(recordPage.totalExceptionCount, 1);
    expect(recordPage.records, hasLength(3));
    expect(rawYearRows.single.userId, 'PM07');
    expect(rawYearRows.single.valueOf(AttendanceMetric.attendanceDays), 1);
    expect(rawYearRows.single.valueOf(AttendanceMetric.checkinRecordCount), 3);
    expect(
      rawYearRows.single.valueOf(AttendanceMetric.normalAttendanceDays),
      1,
    );
    expect(rawYearRows.single.valueOf(AttendanceMetric.timeExceptionCount), 1);
    expect(rawYearRows.single.valueOf(AttendanceMetric.regularWorkHours), 9);
    expect(rawMonthlyRows.single.periodLabel, '2026-11');
  });

  test('replaces a re-synced period instead of double counting it', () async {
    final database = AttendanceDatabase(
      factory: databaseFactoryFfiNoIsolate,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(database.close);

    await database.saveMonthlyReports(
      [_report(workDays: 10)],
      year: 2026,
      periodStart: DateTime(2026, 11, 1),
      periodEndExclusive: DateTime(2026, 11, 16),
    );
    await database.saveMonthlyReports(
      [_report(workDays: 8)],
      year: 2026,
      periodStart: DateTime(2026, 11, 1),
      periodEndExclusive: DateTime(2026, 11, 16),
    );

    final rows = await database.loadSummary(firstYear: 2026, lastYear: 2026);

    expect(rows.single.sourceRecordCount, 1);
    expect(rows.single.valueOf(AttendanceMetric.expectedDays), 8);
  });

  test('excludes no-check-in placeholders from monthly yearly and history summaries', () async {
    final database = AttendanceDatabase(
      factory: databaseFactoryFfiNoIsolate,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(database.close);

    await database.saveCheckinRecords([
      CheckinRecord(
        userId: 'PM07',
        checkinType: '上班打卡',
        exceptionType: '未打卡',
        checkinTime: DateTime(2026, 11, 2, 9),
      ),
      CheckinRecord(
        userId: 'PM07',
        checkinType: '下班打卡',
        exceptionType: '未打卡',
        checkinTime: DateTime(2026, 11, 2, 18),
      ),
      CheckinRecord(
        userId: 'PM07',
        checkinType: '上班打卡',
        checkinTime: DateTime(2026, 11, 3, 9),
      ),
      CheckinRecord(
        userId: 'PM07',
        checkinType: '下班打卡',
        checkinTime: DateTime(2026, 11, 3, 18),
      ),
      CheckinRecord(
        userId: 'PM07',
        checkinType: '上班打卡',
        checkinTime: DateTime(2026, 11, 4, 9),
      ),
      CheckinRecord(
        userId: 'PM07',
        checkinType: '下班打卡',
        exceptionType: '未打卡',
        checkinTime: DateTime(2026, 11, 4, 18),
      ),
    ]);

    final summaries = [
      await database.loadRawMonthlySummary(
        firstMonth: DateTime(2026, 11),
        lastMonth: DateTime(2026, 11),
        userIds: const {'PM07'},
      ),
      await database.loadRawYearSummary(
        firstYear: 2026,
        lastYear: 2026,
        userIds: const {'PM07'},
      ),
      await database.loadRawAllTimeSummary(
        startDate: DateTime(2026, 11, 1),
        endDate: DateTime(2026, 11, 30),
        userIds: const {'PM07'},
      ),
    ];

    for (final rows in summaries) {
      final row = rows.single;
      expect(row.valueOf(AttendanceMetric.attendanceDays), 2);
      expect(row.valueOf(AttendanceMetric.normalAttendanceDays), 1);
      expect(row.valueOf(AttendanceMetric.checkinRecordCount), 3);
      expect(row.valueOf(AttendanceMetric.exceptionCount), 3);
      expect(row.valueOf(AttendanceMetric.exceptionDays), 2);
      expect(row.valueOf(AttendanceMetric.notCheckedInCount), 3);
      expect(row.valueOf(AttendanceMetric.regularWorkHours), 9);
    }
  });

  test(
    'full replacement removes stale records in the covered period',
    () async {
      final database = AttendanceDatabase(
        factory: databaseFactoryFfiNoIsolate,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(database.close);

      await database.saveCheckinRecords([
        CheckinRecord(
          userId: 'PM07',
          checkinType: '上班打卡',
          checkinTime: DateTime(2026, 11, 2, 9),
        ),
        CheckinRecord(
          userId: 'PM07',
          checkinType: '下班打卡',
          checkinTime: DateTime(2026, 11, 3, 18),
        ),
      ]);
      await database.replaceCheckinRecords(
        [
          CheckinRecord(
            userId: 'PM07',
            checkinType: '上班打卡',
            checkinTime: DateTime(2026, 11, 2, 9, 5),
          ),
        ],
        periodStart: DateTime(2026, 11, 1),
        periodEndExclusive: DateTime(2026, 11, 16),
        userIds: const ['PM07'],
      );

      final stats = await database.loadStats();
      expect(stats.checkinRecordCount, 1);
    },
  );

  test(
    'incremental save replaces updated exception data by source key',
    () async {
      final database = AttendanceDatabase(
        factory: databaseFactoryFfiNoIsolate,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(database.close);

      final original = CheckinRecord(
        userId: 'PM07',
        checkinType: '上班打卡',
        checkinTime: DateTime(2026, 11, 2, 9),
      );
      await database.saveCheckinRecords([original]);
      await database.saveCheckinRecords([
        CheckinRecord(
          userId: 'PM07',
          checkinType: '上班打卡',
          exceptionType: '时间异常',
          checkinTime: original.checkinTime,
        ),
      ]);

      final page = await database.loadCheckinRecords(
        startDate: DateTime(2026, 11, 1),
        endDate: DateTime(2026, 11, 30),
        userIds: const {'PM07'},
        dataType: CheckinDataType.all,
      );

      expect(page.records, hasLength(1));
      expect(page.records.single.exceptionType, '时间异常');
      expect(page.totalExceptionCount, 1);
    },
  );
}

MonthlyReport _report({
  int workDays = 10,
  int exceptionDays = 1,
  int lateCount = 1,
}) {
  return MonthlyReport.fromJson({
    'base_info': {
      'name': '吴振国',
      'departs_name': 'Tospino/平台',
      'rule_info': {'groupid': 10, 'groupname': '平台打卡'},
      'acctid': 'PM07',
    },
    'summary_info': {
      'work_days': workDays,
      'regular_days': workDays - exceptionDays,
      'rest_days': 4,
      'except_days': exceptionDays,
      'regular_work_sec': workDays * 28800,
      'standard_work_sec': workDays * 28800,
    },
    'exception_infos': [
      {'exception': 1, 'count': lateCount, 'duration': 60},
    ],
    'sp_items': const [],
    'overwork_info': const {
      'workday_over_sec': 0,
      'restdays_over_sec': 0,
      'holidays_over_sec': 0,
    },
  });
}
