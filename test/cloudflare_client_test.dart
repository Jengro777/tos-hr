import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tospino_hr/config/database_config.dart';
import 'package:tospino_hr/config/wecom_config.dart';
import 'package:tospino_hr/data/attendance_summary.dart';
import 'package:tospino_hr/data/checkin_record.dart';
import 'package:tospino_hr/data/cloudflare_attendance_database.dart';
import 'package:tospino_hr/data/monthly_report.dart';
import 'package:tospino_hr/services/wecom_api_client.dart';

void main() {
  test('uses the Cloudflare WeCom proxy without embedding a secret', () async {
    final requests = <Map<String, dynamic>>[];
    final client = WeComApiClient(
      config: const WecomConfig(
        corpId: 'ww-test',
        agentId: '1000021',
        secret: '',
        proxyEnabled: true,
        remoteConfigured: true,
      ),
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        if (body['action'] == 'check_connection') {
          return http.Response(
            jsonEncode({'errcode': 0, 'errmsg': 'ok'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'errcode': 0,
            'checkindata': [
              {
                'userid': 'zhangsan',
                'checkin_time': 1700000000,
                'checkin_type': '上班打卡',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final connection = await client.checkConnection();
    final records = await client.getCheckinData(
      dataType: CheckinDataType.all,
      start: DateTime(2026, 1, 1),
      end: DateTime(2026, 1, 2),
      userIds: const ['zhangsan'],
    );

    expect(connection.connected, isTrue);
    expect(records.single.userId, 'zhangsan');
    expect(requests.first['action'], 'check_connection');
    expect(requests.last['action'], 'checkin');
    expect(requests.last.toString(), isNot(contains('secret')));
  });

  test('reads attendance data through the Cloudflare database proxy', () async {
    final actions = <String>[];
    final database = CloudflareAttendanceDatabase(
      config: const DatabaseConfig(
        host: 'gateway.example.com',
        port: 4000,
        username: '',
        password: '',
        database: 'tospino_hr',
        proxyEnabled: true,
        remoteConfigured: true,
      ),
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        actions.add('${body['action']}');
        switch (body['action']) {
          case 'load_stats':
            return _json({
              'checkin_record_count': 12,
              'monthly_report_count': 0,
              'attendance_date_count': 4,
              'last_run': null,
            });
          case 'load_checkin_page':
            return _json({
              'records': [
                {
                  'userid': 'zhangsan',
                  'checkin_time': 1700000000,
                  'checkin_type': '上班打卡',
                },
              ],
              'total_count': 1,
              'total_user_count': 1,
              'total_exception_count': 0,
            });
          case 'save_checkins':
            return _json({
              'count': (body['payload']['records'] as List).length,
            });
          default:
            return _json({});
        }
      }),
    );

    final stats = await database.loadStats();
    final page = await database.loadCheckinRecords(
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 31),
      userIds: const {'zhangsan'},
      dataType: CheckinDataType.all,
    );
    final saved = await database.saveCheckinRecords([
      CheckinRecord(
        userId: 'zhangsan',
        checkinTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      ),
    ]);

    expect(stats.checkinRecordCount, 12);
    expect(page.records.single.userId, 'zhangsan');
    expect(saved, 1);
    expect(actions, ['load_stats', 'load_checkin_page', 'save_checkins']);
  });

  test(
    'loads monthly report summaries and merges real attendance days',
    () async {
      final actions = <String>[];
      Map<String, dynamic>? monthlyPayload;
      final database = CloudflareAttendanceDatabase(
        config: const DatabaseConfig(
          host: 'gateway.example.com',
          port: 4000,
          username: '',
          password: '',
          database: 'tospino_hr',
          proxyEnabled: true,
          remoteConfigured: true,
        ),
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          actions.add('${body['action']}');
          switch (body['action']) {
            case 'replace_monthly_reports':
              monthlyPayload = body['payload'] as Map<String, dynamic>;
              return _json({'count': 1});
            case 'load_monthly_report_snapshots':
              return _json([
                {
                  'user_id': 'PM07',
                  'year': 2026,
                  'period_start': DateTime(2026, 11).millisecondsSinceEpoch,
                  'period_end_exclusive': DateTime(
                    2026,
                    12,
                  ).millisecondsSinceEpoch,
                  'report_json': jsonEncode(_monthlyReport().toJson()),
                },
                {
                  'user_id': 'PM07',
                  'year': 2026,
                  'period_start': DateTime(2026, 11).millisecondsSinceEpoch,
                  'period_end_exclusive': DateTime(
                    2026,
                    11,
                    16,
                  ).millisecondsSinceEpoch,
                  'report_json': jsonEncode(_monthlyReport().toJson()),
                },
              ]);
            case 'load_raw_month_summary':
              return _json([
                {
                  'year': 2026,
                  'month': 11,
                  'period_label': null,
                  'name': 'PM07',
                  'user_id': 'PM07',
                  'rule_names': 'Tospino打卡',
                  'departments': '--',
                  'source_record_count': 0,
                  'metrics': {
                    'checkinRecordCount': 40,
                    'attendanceDays': 18,
                    'expectedDays': 20,
                    'normalAttendanceDays': 18,
                    'regularDays': 18,
                    'exceptionDays': 2,
                    'exceptionCount': 3,
                    'regularWorkHours': 144,
                    'standardWorkHours': 160,
                  },
                },
              ]);
            case 'load_raw_year_summary':
              return _json([
                {
                  'year': 2026,
                  'month': null,
                  'period_label': null,
                  'name': 'PM07',
                  'user_id': 'PM07',
                  'rule_names': 'Tospino打卡',
                  'departments': '--',
                  'source_record_count': 0,
                  'metrics': {
                    'checkinRecordCount': 40,
                    'attendanceDays': 18,
                    'expectedDays': 20,
                    'normalAttendanceDays': 18,
                    'regularDays': 18,
                    'exceptionDays': 2,
                    'exceptionCount': 3,
                    'regularWorkHours': 144,
                    'standardWorkHours': 160,
                  },
                },
              ]);
            case 'load_raw_all_summary':
              return _json([
                {
                  'year': 2026,
                  'month': null,
                  'period_label': '2026-11-01~2026-11-30',
                  'name': 'PM07',
                  'user_id': 'PM07',
                  'rule_names': 'Tospino打卡',
                  'departments': '--',
                  'source_record_count': 0,
                  'metrics': {
                    'checkinRecordCount': 40,
                    'attendanceDays': 18,
                    'expectedDays': 20,
                    'normalAttendanceDays': 18,
                    'regularDays': 18,
                    'exceptionDays': 2,
                    'exceptionCount': 3,
                    'regularWorkHours': 144,
                    'standardWorkHours': 160,
                  },
                },
              ]);
            default:
              return _json({});
          }
        }),
      );

      final saved = await database.replaceMonthlyReports(
        [_monthlyReport()],
        year: 2026,
        periodStart: DateTime(2026, 11),
        periodEndExclusive: DateTime(2026, 12),
        userIds: const {'PM07'},
      );
      final rows = await database.loadMonthlySummary(
        firstMonth: DateTime(2026, 11),
        lastMonth: DateTime(2026, 11),
        userIds: const {'PM07'},
      );
      final yearlyRows = await database.loadSummary(
        firstYear: 2026,
        lastYear: 2026,
        userIds: const {'PM07'},
      );
      final historyRows = await database.loadRawAllTimeSummary(
        startDate: DateTime(2026, 11),
        endDate: DateTime(2026, 11, 30),
        userIds: const {'PM07'},
      );

      expect(saved, 1);
      expect(monthlyPayload?['user_ids'], ['PM07']);
      expect(rows.single.valueOf(AttendanceMetric.expectedDays), 20);
      expect(rows.single.valueOf(AttendanceMetric.normalAttendanceDays), 19);
      expect(rows.single.valueOf(AttendanceMetric.attendanceDays), 18);
      expect(rows.single.valueOf(AttendanceMetric.checkinRecordCount), 40);
      expect(yearlyRows.single.valueOf(AttendanceMetric.expectedDays), 20);
      expect(historyRows.single.valueOf(AttendanceMetric.expectedDays), 20);
      expect(historyRows.single.valueOf(AttendanceMetric.attendanceDays), 18);
      expect(
        historyRows.single.valueOf(AttendanceMetric.regularWorkHours),
        144,
      );
      expect(
        historyRows.single.valueOf(AttendanceMetric.standardWorkHours),
        160,
      );
      expect(actions, [
        'replace_monthly_reports',
        'load_monthly_report_snapshots',
        'load_raw_month_summary',
        'load_monthly_report_snapshots',
        'load_raw_year_summary',
        'load_raw_all_summary',
      ]);
    },
  );

  test(
    'only treats complete natural-month report snapshots as synced',
    () async {
      final database = CloudflareAttendanceDatabase(
        config: const DatabaseConfig(
          host: 'gateway.example.com',
          port: 4000,
          username: '',
          password: '',
          database: 'tospino_hr',
          proxyEnabled: true,
          remoteConfigured: true,
        ),
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['action'], 'load_report_snapshot_keys');
          return _json([
            '${DateTime(2026, 10).millisecondsSinceEpoch}|'
                '${DateTime(2026, 10, 16).millisecondsSinceEpoch}|PM07',
            '${DateTime(2026, 11).millisecondsSinceEpoch}|'
                '${DateTime(2026, 12).millisecondsSinceEpoch}|PM07',
          ]);
        }),
      );

      final keys = await database.loadSyncedSnapshotKeys(
        firstMonth: DateTime(2026, 10),
        lastMonth: DateTime(2026, 11),
        userIds: const {'PM07'},
      );

      expect(keys, {'${DateTime(2026, 11).millisecondsSinceEpoch}|PM07'});
    },
  );

  test('loads complete monthly report detail through the proxy', () async {
    final database = CloudflareAttendanceDatabase(
      config: const DatabaseConfig(
        host: 'gateway.example.com',
        port: 4000,
        username: '',
        password: '',
        database: 'tospino_hr',
        proxyEnabled: true,
        remoteConfigured: true,
      ),
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['action'], 'load_monthly_report_snapshots');
        return _json([
          {
            'user_id': 'PM07',
            'year': 2026,
            'period_start': DateTime(2026, 11).millisecondsSinceEpoch,
            'period_end_exclusive': DateTime(2026, 12).millisecondsSinceEpoch,
            'report_json': jsonEncode({
              ..._monthlyReport().toJson(),
              'exception_infos': [
                {'exception': 1, 'count': 2, 'duration': 120},
              ],
              'sp_items': [
                {
                  'type': 1,
                  'name': '年假',
                  'count': 1,
                  'duration': 3600,
                  'time_type': 1,
                },
              ],
              'overwork_info': {'workday_over_sec': 3600},
            }),
          },
        ]);
      }),
    );

    final report = await database.loadMonthlyReport(
      userId: 'PM07',
      month: DateTime(2026, 11),
    );

    expect(report?.summary.workDays, 20);
    expect(report?.exceptions.single.label, '迟到');
    expect(report?.specialItems.single.label, '年假');
    expect(report?.overwork?.workdaySeconds, 3600);
  });

  test('loads only complete monthly reports for annual detail', () async {
    final database = CloudflareAttendanceDatabase(
      config: const DatabaseConfig(
        host: 'gateway.example.com',
        port: 4000,
        username: '',
        password: '',
        database: 'tospino_hr',
        proxyEnabled: true,
        remoteConfigured: true,
      ),
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['action'], 'load_monthly_report_snapshots');
        return _json([
          {
            'user_id': 'PM07',
            'year': 2026,
            'period_start': DateTime(2026, 10).millisecondsSinceEpoch,
            'period_end_exclusive': DateTime(
              2026,
              10,
              16,
            ).millisecondsSinceEpoch,
            'report_json': jsonEncode(_monthlyReport().toJson()),
          },
          {
            'user_id': 'PM07',
            'year': 2026,
            'period_start': DateTime(2026, 11).millisecondsSinceEpoch,
            'period_end_exclusive': DateTime(2026, 12).millisecondsSinceEpoch,
            'report_json': jsonEncode(_monthlyReport().toJson()),
          },
        ]);
      }),
    );

    final reports = await database.loadMonthlyReports(
      firstMonth: DateTime(2026, 10),
      lastMonth: DateTime(2026, 11),
      userIds: const {'PM07'},
    );

    expect(reports, hasLength(1));
    expect(reports.single.periodStart, DateTime(2026, 11));
  });
}

MonthlyReport _monthlyReport() {
  return MonthlyReport.fromJson({
    'base_info': {
      'name': '吴振国',
      'acctid': 'PM07',
      'departs_name': 'Tospino/平台',
      'rule_info': {'groupid': 10, 'groupname': 'Tospino打卡'},
    },
    'summary_info': {
      'work_days': 20,
      'regular_days': 19,
      'rest_days': 8,
      'except_days': 1,
      'regular_work_sec': 576000,
      'standard_work_sec': 576000,
    },
    'exception_infos': const [],
    'sp_items': const [],
  });
}

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);
