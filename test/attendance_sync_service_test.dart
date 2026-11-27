import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tospino_hr/config/wecom_config.dart';
import 'package:tospino_hr/data/attendance_database.dart';
import 'package:tospino_hr/services/attendance_sync_service.dart';
import 'package:tospino_hr/services/wecom_api_client.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('syncs raw daily records only in safe half-month windows', () async {
    var checkinCalls = 0;
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
              'checkin_type': '上班打卡',
              'checkin_time': start + 9 * 3600,
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
    final database = AttendanceDatabase(
      factory: databaseFactoryFfiNoIsolate,
      databasePath: inMemoryDatabasePath,
    );
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
    expect(result.checkinRecordCount, 2);
    expect(stats.checkinRecordCount, 2);
    expect(stats.monthlyReportCount, 0);
    expect(stats.lastRun?.status, 'completed');
    expect(stats.lastRun?.syncMode, 'full');

    final incremental = await service.syncAll(
      firstMonth: DateTime(2026, 11),
      lastMonth: DateTime(2026, 11),
      userIds: const ['PM07'],
      startAt: DateTime(2026, 11, 16),
      mode: AttendanceSyncMode.incremental,
    );
    final incrementalStats = await database.loadStats();

    expect(checkinCalls, 3);
    expect(incremental.windowCount, 1);
    expect(incrementalStats.checkinRecordCount, 2);
    expect(incrementalStats.monthlyReportCount, 0);
    expect(incrementalStats.lastRun?.syncMode, 'incremental');
  });
}

http.Response _jsonResponse(Map<String, Object?> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}
