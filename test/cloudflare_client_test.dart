import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tospino_hr/config/database_config.dart';
import 'package:tospino_hr/config/wecom_config.dart';
import 'package:tospino_hr/data/checkin_record.dart';
import 'package:tospino_hr/data/cloudflare_attendance_database.dart';
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
}

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);
