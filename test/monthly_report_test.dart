import 'package:flutter_test/flutter_test.dart';
import 'package:tospino_hr/data/monthly_report.dart';

void main() {
  test('parses monthly attendance, exception, leave, and overtime data', () {
    final report = MonthlyReport.fromJson({
      'base_info': {
        'record_type': 1,
        'name': '张三',
        'name_ex': 'Three Zhang',
        'departs_name': 'Tospino/HR',
        'rule_info': {'groupid': 10, 'groupname': '标准工时'},
        'acctid': 'ZhangSan',
      },
      'summary_info': {
        'work_days': 20,
        'regular_days': 17,
        'rest_days': 8,
        'except_days': 3,
        'regular_work_sec': 29040,
        'standard_work_sec': 32640,
      },
      'exception_infos': [
        {'exception': 1, 'count': 2, 'duration': 1200},
        {'exception': 3, 'count': 1, 'duration': 0},
      ],
      'sp_items': [
        {
          'type': 1,
          'vacation_id': 2,
          'count': 1,
          'duration': 43200,
          'time_type': 0,
          'name': '年假',
        },
        {'type': 3, 'count': 2, 'duration': 7200, 'time_type': 1, 'name': '出差'},
      ],
      'overwork_info': {
        'workday_over_sec': 5400,
        'restdays_over_sec': 3600,
        'holidays_over_sec': 0,
      },
      'future_field': 'kept',
    });

    expect(report.displayName, '张三');
    expect(report.userId, 'ZhangSan');
    expect(report.baseInfo.groupName, '标准工时');
    expect(report.summary.workDays, 20);
    expect(report.summary.exceptionDays, 3);
    expect(report.summary.regularWorkText, '8 小时 4 分钟');
    expect(report.exceptions.first.label, '迟到');
    expect(report.exceptions.first.durationSeconds, 1200);
    expect(report.specialItems.first.durationText, '0.5天');
    expect(report.specialItems.last.durationText, '2小时');
    expect(report.overwork?.totalText, '2 小时 30 分钟');
    expect(report.rawData['future_field'], 'kept');
  });

  test('formats work durations', () {
    expect(formatWorkDuration(0), '0 分钟');
    expect(formatWorkDuration(1800), '30 分钟');
    expect(formatWorkDuration(7200), '2 小时');
    expect(formatWorkDuration(7500), '2 小时 5 分钟');
  });
}
