import 'package:flutter_test/flutter_test.dart';
import 'package:tospino_hr/data/attendance_summary.dart';
import 'package:tospino_hr/data/monthly_report.dart';

void main() {
  test('merges monthly reports by year and member', () {
    final builder = AttendanceSummaryBuilder()
      ..addReports([
        _report(
          ruleName: '平台打卡',
          workDays: 20,
          exceptionDays: 2,
          lateCount: 2,
          lateDuration: 120,
        ),
        _report(
          ruleName: 'Tospino打卡',
          workDays: 21,
          exceptionDays: 3,
          lateCount: 1,
          lateDuration: 60,
        ),
      ], year: 2026);

    final row = builder.build().single;

    expect(row.year, 2026);
    expect(row.name, '吴振国');
    expect(row.userId, 'PM07');
    expect(row.ruleNames, '平台打卡；Tospino打卡');
    expect(row.sourceRecordCount, 2);
    expect(row.valueOf(AttendanceMetric.expectedDays), 41);
    expect(row.valueOf(AttendanceMetric.exceptionDays), 5);
    expect(row.valueOf(AttendanceMetric.lateCount), 3);
    expect(row.valueOf(AttendanceMetric.lateMinutes), 3);
    expect(row.valueOf(AttendanceMetric.regularWorkHours), 41);
    expect(row.valueOf(AttendanceMetric.annualLeaveHours), 2);
    expect(row.valueOf(AttendanceMetric.correctionCount), 2);
    expect(row.valueOf(AttendanceMetric.businessTripDays), 2);
    expect(row.valueOf(AttendanceMetric.maternityLeaveDays), 4);
    expect(row.valueOf(AttendanceMetric.overtimeHours), 4);
  });

  test('separates the same member across different years', () {
    final builder = AttendanceSummaryBuilder()
      ..addReports([_report()], year: 2025)
      ..addReports([_report()], year: 2026);

    final rows = builder.build();

    expect(rows.map((row) => row.year), [2025, 2026]);
    expect(rows.map((row) => row.name), ['吴振国', '吴振国']);
  });

  test('omits empty pre-employment report periods', () {
    final builder = AttendanceSummaryBuilder()
      ..addReports([
        MonthlyReport.fromJson({
          'base_info': {
            'name': '吴振国',
            'rule_info': {'groupname': '平台打卡'},
            'acctid': 'PM07',
          },
          'summary_info': const {},
          'exception_infos': const [],
          'sp_items': const [],
        }),
      ], year: 2018);

    expect(builder.build(), isEmpty);
  });

  test('builds stable half-month windows below the API date limit', () {
    final windows = buildAttendanceSyncWindows(
      DateTime(2025, 11),
      DateTime(2026, 3),
    );

    expect(windows.length, 10);
    expect(windows.first.label, '2025-11-01 至 2025-11-15');
    expect(windows[1].label, '2025-11-16 至 2025-11-30');
    expect(windows.last.label, '2026-03-16 至 2026-03-31');
    expect(windows.map((window) => window.year).toSet(), {2025, 2026});
    expect(
      windows.every(
        (window) =>
            window.endExclusive.difference(window.start) <=
            const Duration(days: 30),
      ),
      isTrue,
    );
  });

  test('clips incremental windows to the latest database half-month', () {
    final windows = buildAttendanceSyncWindows(
      DateTime(2026, 11),
      DateTime(2026, 11),
      startAt: DateTime(2026, 11, 16),
    );

    expect(windows, hasLength(1));
    expect(windows.single.label, '2026-11-16 至 2026-11-30');
  });
}

MonthlyReport _report({
  String ruleName = '平台打卡',
  int workDays = 20,
  int exceptionDays = 2,
  int lateCount = 2,
  int lateDuration = 120,
}) {
  return MonthlyReport.fromJson({
    'base_info': {
      'record_type': 1,
      'name': '吴振国',
      'departs_name': 'Tospino/平台',
      'rule_info': {'groupid': 10, 'groupname': ruleName},
      'acctid': 'PM07',
    },
    'summary_info': {
      'work_days': workDays,
      'regular_days': workDays - exceptionDays,
      'rest_days': 8,
      'except_days': exceptionDays,
      'regular_work_sec': workDays * 3600,
      'standard_work_sec': workDays * 2880,
    },
    'exception_infos': [
      {'exception': 1, 'count': lateCount, 'duration': lateDuration},
      {'exception': 3, 'count': 1, 'duration': 0},
    ],
    'sp_items': [
      {
        'type': 1,
        'vacation_id': 2,
        'count': 1,
        'duration': 3600,
        'time_type': 1,
        'name': '年假',
      },
      {'type': 2, 'count': 1, 'duration': 0, 'time_type': 0, 'name': '补卡'},
      {'type': 3, 'count': 1, 'duration': 86400, 'time_type': 0, 'name': '出差'},
      {
        'type': 1,
        'vacation_id': 6,
        'count': 1,
        'duration': 172800,
        'time_type': 0,
        'name': '产假',
      },
    ],
    'overwork_info': {
      'workday_over_sec': 3600,
      'restdays_over_sec': 3600,
      'holidays_over_sec': 0,
    },
  });
}
