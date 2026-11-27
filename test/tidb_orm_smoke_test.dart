import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tospino_hr/config/app_runtime_config.dart';
import 'package:tospino_hr/data/attendance_storage.dart';
import 'package:tospino_hr/data/checkin_record.dart';
import 'package:tospino_hr/data/tidb_attendance_database.dart';

void main() {
  final enabled = Platform.environment['RUN_TIDB_SMOKE'] == 'true';

  test(
    'reads TiDB attendance data through the ORM',
    () async {
      final runtime = await loadAppRuntimeConfig();
      final database = TiDbAttendanceDatabase(config: runtime.database);
      addTearDown(database.close);

      final connection = await database.checkConnection();
      expect(connection.connected, isTrue, reason: connection.message);

      final stats = await database.loadStats();
      final bounds = await database.loadCheckinDateBounds();
      final latestReportAt = await database.loadLatestMonthlyReportTime();
      final now = DateTime.now();
      final monthly = await database.loadMonthlySummary(
        firstMonth: DateTime(now.year, now.month),
        lastMonth: DateTime(now.year, now.month),
      );
      final monthlyDetail = monthly.isEmpty
          ? null
          : await database.loadMonthlyReport(
              userId: monthly.first.userId,
              month: DateTime(now.year, now.month),
            );
      final annualReports = monthly.isEmpty
          ? const <MonthlyReportRecord>[]
          : await database.loadMonthlyReports(
              firstMonth: DateTime(now.year),
              lastMonth: DateTime(now.year, 12),
              userIds: {monthly.first.userId},
            );
      final yearly = await database.loadSummary(
        firstYear: now.year,
        lastYear: now.year,
      );
      final histories = bounds == null
          ? const []
          : await database.loadRawAllTimeSummary(
              startDate: bounds.firstDate,
              endDate: bounds.lastDate,
            );
      final page = await database.loadCheckinRecords(
        startDate: bounds?.firstDate ?? DateTime(2018),
        endDate: bounds?.lastDate ?? now,
        userIds: const {},
        dataType: CheckinDataType.all,
        limit: 5,
      );

      expect(stats.checkinRecordCount, greaterThan(0));
      expect(stats.monthlyReportCount, greaterThan(0));
      expect(latestReportAt, isNotNull);
      expect(monthly, isNotEmpty);
      expect(monthlyDetail, isNotNull);
      expect(annualReports, isNotEmpty);
      expect(yearly, isNotEmpty);
      expect(histories, isNotEmpty);
      expect(page.records, isNotEmpty);
      // ignore: avoid_print
      print(
        'TiDB ORM smoke: records=${stats.checkinRecordCount}, '
        'monthly=${monthly.length}, yearly=${yearly.length}, '
        'history=${histories.length}, page=${page.records.length}',
      );
    },
    skip: enabled ? false : 'Set RUN_TIDB_SMOKE=true to use app.local.yaml',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
