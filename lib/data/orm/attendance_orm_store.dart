import 'dart:convert';

import 'package:dartonic_core/dartonic_core.dart';

import '../attendance_storage.dart';
import '../attendance_summary.dart';
import '../checkin_record.dart';
import '../monthly_report.dart';
import 'attendance_schema.dart';

class AttendanceOrmStore {
  AttendanceOrmStore({
    required this.database,
    AttendanceOrmTables? tables,
    this.monthlyReportsEnabled = true,
  }) : tables = tables ?? AttendanceOrmTables();

  final DartonicDb database;
  final AttendanceOrmTables tables;
  final bool monthlyReportsEnabled;

  Future<void> ping() async {
    await database
        .select({'record_count': countAll()})
        .from(tables.checkins)
        .first();
  }

  Future<CheckinRecordPage> loadCheckinRecords({
    required DateTime startDate,
    required DateTime endDate,
    required Set<String> userIds,
    required CheckinDataType dataType,
    int limit = 200,
    int offset = 0,
  }) async {
    final filter = _checkinFilter(
      startDate: startDate,
      endDate: endDate,
      userIds: userIds,
      dataType: dataType,
    );
    final totals = await database
        .select({
          'total_count': countAll(),
          'user_count': count(tables.checkins.userId, distinct: true),
          'exception_count': SqlExpression(
            'SUM(CASE WHEN '
            '${tables.checkins.exceptionType.toSqlIdentifier()} <> '
            "'' THEN 1 ELSE 0 END)",
          ),
        })
        .from(tables.checkins)
        .where(filter)
        .first();
    final rows = await database
        .select()
        .from(tables.checkins)
        .where(filter)
        .orderBy(tables.checkins.checkinAt, Order.desc)
        .limit(limit)
        .offset(offset);
    return CheckinRecordPage(
      records: rows.map(_checkinFromRow).toList(growable: false),
      totalCount: _intValue(totals?.raw['total_count']),
      totalUserCount: _intValue(totals?.raw['user_count']),
      totalExceptionCount: _intValue(totals?.raw['exception_count']),
    );
  }

  Future<int> saveCheckinRecords(Iterable<CheckinRecord> records) async {
    final items = _uniqueCheckins(records);
    if (items.isEmpty) {
      return 0;
    }
    await database.transaction((transaction) async {
      await _replaceCheckinBatches(transaction, items);
    });
    return items.length;
  }

  Future<int> replaceCheckinRecords(
    Iterable<CheckinRecord> records, {
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    required Iterable<String> userIds,
  }) async {
    final items = _uniqueCheckins(records);
    final ids = userIds.toSet().toList(growable: false);
    if (ids.isEmpty) {
      return 0;
    }
    await database.transaction((transaction) async {
      await transaction
          .delete(tables.checkins)
          .where(
            and([
              _atLeastDate(tables.checkins.recordDate, periodStart),
              _beforeDate(tables.checkins.recordDate, periodEndExclusive),
              inArray(tables.checkins.userId, ids),
            ]),
          );
      if (items.isNotEmpty) {
        await _insertCheckinBatches(transaction, items);
      }
    });
    return items.length;
  }

  Future<Set<String>> loadSyncedWindowKeys({
    required DateTime firstMonth,
    required DateTime lastMonth,
    required Set<String> userIds,
  }) async {
    final conditions = <Condition>[
      _atLeastInt(
        tables.syncWindows.periodStart,
        DateTime(firstMonth.year, firstMonth.month).millisecondsSinceEpoch,
      ),
      _lessThanInt(
        tables.syncWindows.periodStart,
        DateTime(lastMonth.year, lastMonth.month + 1).millisecondsSinceEpoch,
      ),
    ];
    if (userIds.isNotEmpty) {
      conditions.add(
        inArray(tables.syncWindows.userId, userIds.toList(growable: false)),
      );
    }
    final rows = await database
        .select([tables.syncWindows.userId, tables.syncWindows.periodStart])
        .from(tables.syncWindows)
        .where(and(conditions));
    return {
      for (final row in rows)
        '${row.read(tables.syncWindows.periodStart)}|'
            '${row.read(tables.syncWindows.userId)}',
    };
  }

  Future<void> markSyncWindows({
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    required Iterable<String> userIds,
  }) async {
    final ids = userIds.toSet().toList(growable: false);
    if (ids.isEmpty) {
      return;
    }
    final syncedAt = DateTime.now().millisecondsSinceEpoch;
    final values = [
      for (final userId in ids)
        <ColumnValue<Object?>>[
          tables.syncWindows.sourceKey.value(
            '${periodStart.millisecondsSinceEpoch}|$userId',
          ),
          tables.syncWindows.userId.value(userId),
          tables.syncWindows.periodStart.value(
            periodStart.millisecondsSinceEpoch,
          ),
          tables.syncWindows.periodEndExclusive.value(
            periodEndExclusive.millisecondsSinceEpoch,
          ),
          tables.syncWindows.syncedAt.value(syncedAt),
        ],
    ];
    await database
        .insert(tables.syncWindows)
        .valuesMany(values)
        .onConflictDoUpdate(
          target: [tables.syncWindows.sourceKey],
          set: [
            tables.syncWindows.periodEndExclusive.value(
              periodEndExclusive.millisecondsSinceEpoch,
            ),
            tables.syncWindows.syncedAt.value(syncedAt),
          ],
        );
  }

  Future<AttendanceDatabaseStats> loadStats() async {
    final totals = await database
        .select({
          'record_count': countAll(),
          'date_count': count(tables.checkins.recordDate, distinct: true),
        })
        .from(tables.checkins)
        .first();
    var monthlyReportCount = 0;
    if (monthlyReportsEnabled) {
      final reportTotals = await database
          .select({'report_count': countAll()})
          .from(tables.monthlyReports)
          .first();
      monthlyReportCount = _intValue(reportTotals?.raw['report_count']);
    }
    final lastRun = await _latestSyncRun();
    return AttendanceDatabaseStats(
      checkinRecordCount: _intValue(totals?.raw['record_count']),
      monthlyReportCount: monthlyReportCount,
      attendanceDateCount: _intValue(totals?.raw['date_count']),
      lastRun: lastRun,
    );
  }

  Future<int> startSyncRun({
    required DateTime firstMonth,
    required DateTime lastMonth,
    required int userCount,
    required AttendanceSyncMode mode,
  }) async {
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    await database.insert(tables.syncRuns).values([
      tables.syncRuns.startedAt.value(startedAt),
      tables.syncRuns.firstMonth.value(_monthKey(firstMonth)),
      tables.syncRuns.lastMonth.value(_monthKey(lastMonth)),
      tables.syncRuns.userCount.value(userCount),
      tables.syncRuns.syncMode.value(mode.name),
      tables.syncRuns.status.value('running'),
      tables.syncRuns.recordCount.value(0),
      tables.syncRuns.reportCount.value(0),
    ]);
    final row = await database
        .select([tables.syncRuns.id])
        .from(tables.syncRuns)
        .where(eq(tables.syncRuns.startedAt, startedAt))
        .orderBy(tables.syncRuns.id, Order.desc)
        .first();
    return row?.read(tables.syncRuns.id) ?? 0;
  }

  Future<void> finishSyncRun(
    int id, {
    required bool succeeded,
    required int recordCount,
    required int reportCount,
    String? errorMessage,
  }) async {
    await database
        .update(tables.syncRuns)
        .set([
          tables.syncRuns.completedAt.value(
            DateTime.now().millisecondsSinceEpoch,
          ),
          tables.syncRuns.status.value(succeeded ? 'completed' : 'failed'),
          tables.syncRuns.recordCount.value(recordCount),
          tables.syncRuns.reportCount.value(reportCount),
          nullableValue(tables.syncRuns.errorMessage, errorMessage),
        ])
        .where(eq(tables.syncRuns.id, id));
  }

  Future<AttendanceDateBounds?> loadCheckinDateBounds({
    Set<String> userIds = const {},
  }) async {
    final query = database
        .select({
          'first_date': min(tables.checkins.recordDate),
          'last_date': max(tables.checkins.recordDate),
        })
        .from(tables.checkins);
    if (userIds.isNotEmpty) {
      query.where(
        inArray(tables.checkins.userId, userIds.toList(growable: false)),
      );
    }
    final row = await query.first();
    final firstDate = tables.checkins.recordDate.decode(row?.raw['first_date']);
    final lastDate = tables.checkins.recordDate.decode(row?.raw['last_date']);
    return firstDate == null || lastDate == null
        ? null
        : AttendanceDateBounds(firstDate: firstDate, lastDate: lastDate);
  }

  Future<DateTime?> loadLatestCheckinTime() async {
    final row = await database
        .select({'latest_checkin_at': max(tables.checkins.checkinAt)})
        .from(tables.checkins)
        .first();
    final value = row?.raw['latest_checkin_at'];
    if (value == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(_intValue(value));
  }

  Future<List<AttendanceSummaryRow>> loadRawYearSummary({
    required int firstYear,
    required int lastYear,
    Set<String> userIds = const {},
  }) {
    return _loadRawSummary(
      startDate: DateTime(firstYear),
      endDate: DateTime(lastYear, 12, 31),
      period: _SummaryPeriod.year,
      userIds: userIds,
    );
  }

  Future<List<AttendanceSummaryRow>> loadRawMonthlySummary({
    required DateTime firstMonth,
    required DateTime lastMonth,
    Set<String> userIds = const {},
  }) {
    return _loadRawSummary(
      startDate: DateTime(firstMonth.year, firstMonth.month),
      endDate: DateTime(
        lastMonth.year,
        lastMonth.month + 1,
      ).subtract(const Duration(days: 1)),
      period: _SummaryPeriod.month,
      userIds: userIds,
    );
  }

  Future<List<AttendanceSummaryRow>> loadRawAllTimeSummary({
    required DateTime startDate,
    required DateTime endDate,
    Set<String> userIds = const {},
  }) {
    return _loadRawSummary(
      startDate: startDate,
      endDate: endDate,
      period: _SummaryPeriod.all,
      userIds: userIds,
    );
  }

  Future<List<AttendanceSummaryRow>> loadDailyCheckinSummary({
    required DateTime startDate,
    required DateTime endDate,
    Set<String> userIds = const {},
  }) async {
    final inner = _dailyQuery(
      startDate: startDate,
      endDate: endDate,
      userIds: userIds,
    );
    final cte = database.withCte('attendance_daily').as(inner);
    final daily = _DailyColumns();
    final rows = await database
        .fromCte(cte)
        .select({
          'user_id': daily.userId,
          'record_count': _sumOf(daily.recordCount),
          'attendance_days': SqlExpression(
            'COUNT(DISTINCT ${daily.recordDate.toSqlIdentifier()})',
          ),
          'exception_count': _sumOf(daily.exceptionCount),
          'exception_days': SqlExpression(
            'SUM(CASE WHEN ${daily.exceptionCount.toSqlIdentifier()} > 0 '
            'THEN 1 ELSE 0 END)',
          ),
          'location_exception_count': _sumOf(daily.locationCount),
          'device_exception_count': _sumOf(daily.deviceCount),
        })
        .groupBy([daily.userId])
        .orderBy(daily.userId);
    final metadata = await _loadUserMetadata();
    return [
      for (final row in rows)
        AttendanceSummaryRow(
          year: startDate.year,
          periodLabelOverride: '${_dateKey(startDate)} 至 ${_dateKey(endDate)}',
          name:
              metadata[row.raw['user_id']]?.name ??
              row.raw['user_id'].toString(),
          userId: row.raw['user_id'].toString(),
          ruleNames: metadata[row.raw['user_id']]?.ruleNames ?? '--',
          departments: metadata[row.raw['user_id']]?.departments ?? '--',
          sourceRecordCount: 0,
          metrics: Map<AttendanceMetric, double>.unmodifiable({
            for (final metric in AttendanceMetric.values) metric: 0.0,
            AttendanceMetric.checkinRecordCount: _doubleValue(
              row.raw['record_count'],
            ),
            AttendanceMetric.attendanceDays: _doubleValue(
              row.raw['attendance_days'],
            ),
            AttendanceMetric.exceptionCount: _doubleValue(
              row.raw['exception_count'],
            ),
            AttendanceMetric.exceptionDays: _doubleValue(
              row.raw['exception_days'],
            ),
            AttendanceMetric.locationExceptionCount: _doubleValue(
              row.raw['location_exception_count'],
            ),
            AttendanceMetric.deviceExceptionCount: _doubleValue(
              row.raw['device_exception_count'],
            ),
          }),
        ),
    ];
  }

  Future<int> saveMonthlyReports(
    Iterable<MonthlyReport> reports, {
    required int year,
    required DateTime periodStart,
    required DateTime periodEndExclusive,
  }) async {
    final items = reports.toList(growable: false);
    if (items.isEmpty) {
      return 0;
    }
    await database.transaction((transaction) async {
      await _replaceMonthlyReportRows(
        transaction,
        items,
        year: year,
        periodStart: periodStart,
        periodEndExclusive: periodEndExclusive,
      );
    });
    return items.length;
  }

  Future<int> replaceMonthlyReports(
    Iterable<MonthlyReport> reports, {
    required int year,
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    required Iterable<String> userIds,
  }) async {
    final items = reports.toList(growable: false);
    final ids = userIds.toSet().toList(growable: false);
    if (ids.isEmpty) {
      return 0;
    }
    await database.transaction((transaction) async {
      await transaction
          .delete(tables.monthlyReports)
          .where(
            and([
              eq(
                tables.monthlyReports.periodStart,
                periodStart.millisecondsSinceEpoch,
              ),
              inArray(tables.monthlyReports.userId, ids),
            ]),
          );
      if (items.isNotEmpty) {
        await _insertMonthlyReports(
          transaction,
          items,
          year: year,
          periodStart: periodStart,
          periodEndExclusive: periodEndExclusive,
        );
      }
    });
    return items.length;
  }

  Future<List<AttendanceSummaryRow>> loadSummary({
    required int firstYear,
    required int lastYear,
    Set<String> userIds = const {},
  }) async {
    final query = database
        .select([
          tables.monthlyReports.year,
          tables.monthlyReports.userId,
          tables.monthlyReports.reportJson,
        ])
        .from(tables.monthlyReports)
        .where(
          and([
            _atLeastInt(tables.monthlyReports.year, firstYear),
            _atMostInt(tables.monthlyReports.year, lastYear),
            if (userIds.isNotEmpty)
              inArray(
                tables.monthlyReports.userId,
                userIds.toList(growable: false),
              ),
          ]),
        )
        .orderBy(tables.monthlyReports.year)
        .orderBy(tables.monthlyReports.userId)
        .orderBy(tables.monthlyReports.periodStart);
    final rows = await query;
    final builder = AttendanceSummaryBuilder();
    for (final row in rows) {
      final report = _monthlyReportFromRow(row);
      if (report != null) {
        builder.addReports([
          report,
        ], year: row.read(tables.monthlyReports.year) ?? firstYear);
      }
    }
    final rawRows = await loadRawYearSummary(
      firstYear: firstYear,
      lastYear: lastYear,
      userIds: userIds,
    );
    final rawByKey = {
      for (final row in rawRows) '${row.year}|${row.userId}': row,
    };
    return [
      for (final row in builder.build())
        row
            .withMetric(
              AttendanceMetric.checkinRecordCount,
              rawByKey['${row.year}|${row.userId}']?.valueOf(
                    AttendanceMetric.checkinRecordCount,
                  ) ??
                  0,
            )
            .withMetric(
              AttendanceMetric.attendanceDays,
              rawByKey['${row.year}|${row.userId}']?.valueOf(
                    AttendanceMetric.attendanceDays,
                  ) ??
                  0,
            ),
    ];
  }

  Future<List<AttendanceSummaryRow>> loadMonthlySummary({
    required DateTime firstMonth,
    required DateTime lastMonth,
    Set<String> userIds = const {},
  }) async {
    final rangeStart = DateTime(firstMonth.year, firstMonth.month);
    final rangeEnd = DateTime(lastMonth.year, lastMonth.month + 1);
    final query = database
        .select([
          tables.monthlyReports.userId,
          tables.monthlyReports.periodStart,
          tables.monthlyReports.reportJson,
        ])
        .from(tables.monthlyReports)
        .where(
          and([
            _atLeastInt(
              tables.monthlyReports.periodStart,
              rangeStart.millisecondsSinceEpoch,
            ),
            _lessThanInt(
              tables.monthlyReports.periodStart,
              rangeEnd.millisecondsSinceEpoch,
            ),
            if (userIds.isNotEmpty)
              inArray(
                tables.monthlyReports.userId,
                userIds.toList(growable: false),
              ),
          ]),
        )
        .orderBy(tables.monthlyReports.periodStart)
        .orderBy(tables.monthlyReports.userId);
    final rows = await query;
    final builder = AttendanceMonthlySummaryBuilder();
    for (final row in rows) {
      final report = _monthlyReportFromRow(row);
      final periodStart = DateTime.fromMillisecondsSinceEpoch(
        row.read(tables.monthlyReports.periodStart) ?? 0,
      );
      if (report != null) {
        builder.addReports(
          [report],
          year: periodStart.year,
          month: periodStart.month,
        );
      }
    }
    final rawRows = await loadRawMonthlySummary(
      firstMonth: firstMonth,
      lastMonth: lastMonth,
      userIds: userIds,
    );
    final rawByKey = {
      for (final row in rawRows) '${row.periodLabel}|${row.userId}': row,
    };
    return [
      for (final row in builder.build())
        row
            .withMetric(
              AttendanceMetric.checkinRecordCount,
              rawByKey['${row.periodLabel}|${row.userId}']?.valueOf(
                    AttendanceMetric.checkinRecordCount,
                  ) ??
                  0,
            )
            .withMetric(
              AttendanceMetric.attendanceDays,
              rawByKey['${row.periodLabel}|${row.userId}']?.valueOf(
                    AttendanceMetric.attendanceDays,
                  ) ??
                  0,
            ),
    ];
  }

  Future<List<AttendanceSummaryRow>> loadAllTimeSummary({
    required DateTime firstMonth,
    required DateTime lastMonth,
    Set<String> userIds = const {},
  }) async {
    final monthlyRows = await loadMonthlySummary(
      firstMonth: firstMonth,
      lastMonth: lastMonth,
      userIds: userIds,
    );
    final rows = aggregateAttendanceAllTime(monthlyRows);
    final endDate = DateTime(
      lastMonth.year,
      lastMonth.month + 1,
    ).subtract(const Duration(days: 1));
    final rawRows = await loadRawAllTimeSummary(
      startDate: DateTime(firstMonth.year, firstMonth.month),
      endDate: endDate,
      userIds: userIds,
    );
    final rawByUser = {for (final row in rawRows) row.userId: row};
    return [
      for (final row in rows)
        row
            .withMetric(
              AttendanceMetric.checkinRecordCount,
              rawByUser[row.userId]?.valueOf(
                    AttendanceMetric.checkinRecordCount,
                  ) ??
                  0,
            )
            .withMetric(
              AttendanceMetric.attendanceDays,
              rawByUser[row.userId]?.valueOf(AttendanceMetric.attendanceDays) ??
                  row.valueOf(AttendanceMetric.attendanceDays),
            ),
    ];
  }

  Future<Set<String>> loadSyncedSnapshotKeys({
    required DateTime firstMonth,
    required DateTime lastMonth,
    required Set<String> userIds,
  }) async {
    final rangeStart = DateTime(firstMonth.year, firstMonth.month);
    final rangeEnd = DateTime(lastMonth.year, lastMonth.month + 1);
    final rows = await database
        .select([
          tables.monthlyReports.userId,
          tables.monthlyReports.periodStart,
        ])
        .from(tables.monthlyReports)
        .where(
          and([
            _atLeastInt(
              tables.monthlyReports.periodStart,
              rangeStart.millisecondsSinceEpoch,
            ),
            _lessThanInt(
              tables.monthlyReports.periodStart,
              rangeEnd.millisecondsSinceEpoch,
            ),
            if (userIds.isNotEmpty)
              inArray(
                tables.monthlyReports.userId,
                userIds.toList(growable: false),
              ),
          ]),
        );
    return {
      for (final row in rows)
        '${row.read(tables.monthlyReports.periodStart)}|'
            '${row.read(tables.monthlyReports.userId)}',
    };
  }

  Future<List<AttendanceSummaryRow>> _loadRawSummary({
    required DateTime startDate,
    required DateTime endDate,
    required _SummaryPeriod period,
    required Set<String> userIds,
  }) async {
    final inner = _dailyQuery(
      startDate: startDate,
      endDate: endDate,
      userIds: userIds,
      period: period,
    );
    final cte = database.withCte('attendance_daily').as(inner);
    final daily = _DailyColumns();
    final rows = await database
        .fromCte(cte)
        .select({
          'user_id': daily.userId,
          'period': daily.period,
          'group_name': expression('MAX(${daily.groupName.toSqlIdentifier()})'),
          'record_count': _sumOf(daily.recordCount),
          'attendance_days': _sumOf(daily.attendedDay),
          'normal_attendance_days': SqlExpression(
            'SUM(CASE WHEN '
            '${daily.workCount.toSqlIdentifier()} > 0 AND '
            '${daily.exceptionCount.toSqlIdentifier()} = 0 '
            'THEN 1 ELSE 0 END)',
          ),
          'work_ms': SqlExpression(
            'SUM(COALESCE('
            '${daily.lastWorkAt.toSqlIdentifier()} - '
            '${daily.firstWorkAt.toSqlIdentifier()}, 0))',
          ),
          'exception_count': _sumOf(daily.exceptionCount),
          'exception_days': SqlExpression(
            'SUM(CASE WHEN ${daily.exceptionCount.toSqlIdentifier()} > 0 '
            'THEN 1 ELSE 0 END)',
          ),
          'time_exception_count': _sumOf(daily.timeExceptionCount),
          'not_checked_count': _sumOf(daily.notCheckedCount),
          'wifi_exception_count': _sumOf(daily.wifiExceptionCount),
          'location_count': _sumOf(daily.locationCount),
          'device_count': _sumOf(daily.deviceCount),
        })
        .groupBy([daily.userId, daily.period])
        .orderBy(daily.period, Order.desc)
        .orderBy(daily.userId);
    return [
      for (final row in rows)
        _summaryFromRow(
          row,
          startDate: startDate,
          endDate: endDate,
          includePeriod: period != _SummaryPeriod.all,
        ),
    ];
  }

  QueryBuilder _dailyQuery({
    required DateTime startDate,
    required DateTime endDate,
    required Set<String> userIds,
    _SummaryPeriod period = _SummaryPeriod.month,
  }) {
    final conditions = <Condition>[
      _atLeastDate(tables.checkins.recordDate, startDate),
      _atMostDate(tables.checkins.recordDate, endDate),
      if (userIds.isNotEmpty)
        inArray(tables.checkins.userId, userIds.toList(growable: false)),
    ];
    final recordDate = tables.checkins.recordDate.toSqlIdentifier();
    final checkinType = tables.checkins.checkinType.toSqlIdentifier();
    final exceptionType = tables.checkins.exceptionType.toSqlIdentifier();
    return database
        .select({
          'user_id': tables.checkins.userId,
          'record_date': tables.checkins.recordDate,
          'period': switch (period) {
            _SummaryPeriod.year => SqlExpression('SUBSTR($recordDate, 1, 4)'),
            _SummaryPeriod.month => SqlExpression('SUBSTR($recordDate, 1, 7)'),
            _SummaryPeriod.all => const SqlExpression("''"),
          },
          'group_name': max(tables.checkins.groupName),
          'record_count': countAll(),
          'work_count': _conditionalSum("$checkinType IN ('上班打卡', '下班打卡')"),
          'attended_day': SqlExpression(
            'MAX(CASE WHEN '
            "$checkinType IN ('上班打卡', '下班打卡') "
            'THEN 1 ELSE 0 END)',
          ),
          'first_work_at': SqlExpression(
            'MIN(CASE WHEN '
            "$checkinType IN ('上班打卡', '下班打卡') "
            'THEN ${tables.checkins.checkinAt.toSqlIdentifier()} END)',
          ),
          'last_work_at': SqlExpression(
            'MAX(CASE WHEN '
            "$checkinType IN ('上班打卡', '下班打卡') "
            'THEN ${tables.checkins.checkinAt.toSqlIdentifier()} END)',
          ),
          'exception_count': _conditionalSum("$exceptionType <> ''"),
          'time_exception_count': _conditionalSum(
            "$exceptionType LIKE '%时间异常%'",
          ),
          'not_checked_count': _conditionalSum("$exceptionType LIKE '%未打卡%'"),
          'wifi_exception_count': _conditionalSum(
            "LOWER($exceptionType) LIKE '%wifi%'",
          ),
          'location_count': _conditionalSum("$exceptionType LIKE '%地点异常%'"),
          'device_count': _conditionalSum("$exceptionType LIKE '%非常用设备%'"),
        })
        .from(tables.checkins)
        .where(and(conditions))
        .groupBy([tables.checkins.userId, tables.checkins.recordDate]);
  }

  AttendanceSummaryRow _summaryFromRow(
    RowMap row, {
    required DateTime startDate,
    required DateTime endDate,
    required bool includePeriod,
  }) {
    final period = row.raw['period']?.toString() ?? '';
    final userId = row.raw['user_id']?.toString() ?? '';
    final groupName = row.raw['group_name']?.toString() ?? '';
    return AttendanceSummaryRow(
      year: includePeriod && period.length >= 4
          ? int.tryParse(period.substring(0, 4)) ?? startDate.year
          : startDate.year,
      month: includePeriod && period.length >= 7
          ? int.tryParse(period.substring(5, 7))
          : null,
      periodLabelOverride: includePeriod
          ? null
          : '${_dateKey(startDate)}~${_dateKey(endDate)}',
      name: userId,
      userId: userId,
      ruleNames: groupName.isEmpty ? '--' : groupName,
      departments: '--',
      sourceRecordCount: 0,
      metrics: Map<AttendanceMetric, double>.unmodifiable({
        for (final metric in AttendanceMetric.values) metric: 0.0,
        AttendanceMetric.checkinRecordCount: _doubleValue(
          row.raw['record_count'],
        ),
        AttendanceMetric.attendanceDays: _doubleValue(
          row.raw['attendance_days'],
        ),
        AttendanceMetric.normalAttendanceDays: _doubleValue(
          row.raw['normal_attendance_days'],
        ),
        AttendanceMetric.exceptionDays: _doubleValue(row.raw['exception_days']),
        AttendanceMetric.exceptionCount: _doubleValue(
          row.raw['exception_count'],
        ),
        AttendanceMetric.regularWorkHours:
            _doubleValue(row.raw['work_ms']) / 3600000,
        AttendanceMetric.timeExceptionCount: _doubleValue(
          row.raw['time_exception_count'],
        ),
        AttendanceMetric.notCheckedInCount: _doubleValue(
          row.raw['not_checked_count'],
        ),
        AttendanceMetric.wifiExceptionCount: _doubleValue(
          row.raw['wifi_exception_count'],
        ),
        AttendanceMetric.locationExceptionCount: _doubleValue(
          row.raw['location_count'],
        ),
        AttendanceMetric.deviceExceptionCount: _doubleValue(
          row.raw['device_count'],
        ),
      }),
    );
  }

  List<CheckinRecord> _uniqueCheckins(Iterable<CheckinRecord> records) {
    return {for (final record in records) record.sourceKey: record}.values
        .toList(growable: false);
  }

  Future<void> _replaceCheckinBatches(
    Database executor,
    List<CheckinRecord> records,
  ) async {
    const chunkSize = 50;
    for (var start = 0; start < records.length; start += chunkSize) {
      final end = (start + chunkSize).clamp(0, records.length);
      final chunk = records.sublist(start, end);
      await executor
          .delete(tables.checkins)
          .where(
            inArray(
              tables.checkins.sourceKey,
              chunk.map((record) => record.sourceKey).toList(growable: false),
            ),
          );
      await _insertCheckinBatches(executor, chunk);
    }
  }

  Future<void> _insertCheckinBatches(
    Database executor,
    List<CheckinRecord> records,
  ) async {
    const chunkSize = 50;
    final syncedAt = DateTime.now().millisecondsSinceEpoch;
    for (var start = 0; start < records.length; start += chunkSize) {
      final end = (start + chunkSize).clamp(0, records.length);
      final rows = [
        for (final record in records.sublist(start, end))
          <ColumnValue<Object?>>[
            tables.checkins.sourceKey.value(record.sourceKey),
            tables.checkins.userId.value(record.userId),
            tables.checkins.recordDate.value(record.checkinTime),
            tables.checkins.checkinAt.value(
              record.checkinTime.millisecondsSinceEpoch,
            ),
            tables.checkins.checkinType.value(record.checkinType),
            tables.checkins.exceptionType.value(record.exceptionType),
            tables.checkins.groupName.value(record.groupName),
            nullableValue(tables.checkins.groupId, record.groupId),
            nullableValue(tables.checkins.scheduleId, record.scheduleId),
            nullableValue(tables.checkins.timelineId, record.timelineId),
            tables.checkins.locationTitle.value(record.locationTitle),
            tables.checkins.locationDetail.value(record.locationDetail),
            tables.checkins.wifiName.value(record.wifiName),
            tables.checkins.wifiMac.value(record.wifiMac),
            tables.checkins.notes.value(record.notes),
            tables.checkins.deviceId.value(record.deviceId),
            nullableValue(
              tables.checkins.scheduleCheckinAt,
              record.scheduleCheckinTime?.millisecondsSinceEpoch,
            ),
            nullableValue(tables.checkins.latitude, record.latitude),
            nullableValue(tables.checkins.longitude, record.longitude),
            tables.checkins.mediaIds.value(record.mediaIds),
            tables.checkins.syncedAt.value(syncedAt),
          ],
      ];
      await executor.insert(tables.checkins).valuesMany(rows);
    }
  }

  Future<void> _replaceMonthlyReportRows(
    Database executor,
    List<MonthlyReport> reports, {
    required int year,
    required DateTime periodStart,
    required DateTime periodEndExclusive,
  }) async {
    await executor
        .delete(tables.monthlyReports)
        .where(
          inArray(tables.monthlyReports.sourceKey, [
            for (final report in reports)
              '$year|${report.userId}|${_dateKey(periodStart)}',
          ]),
        );
    await _insertMonthlyReports(
      executor,
      reports,
      year: year,
      periodStart: periodStart,
      periodEndExclusive: periodEndExclusive,
    );
  }

  Future<void> _insertMonthlyReports(
    Database executor,
    List<MonthlyReport> reports, {
    required int year,
    required DateTime periodStart,
    required DateTime periodEndExclusive,
  }) async {
    final syncedAt = DateTime.now().millisecondsSinceEpoch;
    final rows = [
      for (final report in reports)
        <ColumnValue<Object?>>[
          tables.monthlyReports.sourceKey.value(
            '$year|${report.userId}|${_dateKey(periodStart)}',
          ),
          tables.monthlyReports.userId.value(report.userId),
          tables.monthlyReports.year.value(year),
          tables.monthlyReports.periodStart.value(
            periodStart.millisecondsSinceEpoch,
          ),
          tables.monthlyReports.periodEndExclusive.value(
            periodEndExclusive.millisecondsSinceEpoch,
          ),
          tables.monthlyReports.reportJson.value(jsonEncode(report.toJson())),
          tables.monthlyReports.syncedAt.value(syncedAt),
        ],
    ];
    if (rows.isNotEmpty) {
      await executor.insert(tables.monthlyReports).valuesMany(rows);
    }
  }

  Future<AttendanceSyncRun?> _latestSyncRun() async {
    final row = await database
        .select()
        .from(tables.syncRuns)
        .orderBy(tables.syncRuns.startedAt, Order.desc)
        .first();
    return row == null ? null : AttendanceSyncRun.fromMap(row.raw);
  }

  Future<Map<String, _UserMetadata>> _loadUserMetadata() async {
    if (!monthlyReportsEnabled) {
      return const {};
    }
    final rows = await database
        .select([
          tables.monthlyReports.userId,
          tables.monthlyReports.reportJson,
        ])
        .from(tables.monthlyReports)
        .orderBy(tables.monthlyReports.periodStart, Order.desc);
    final metadata = <String, _UserMetadata>{};
    for (final row in rows) {
      final userId = row.read(tables.monthlyReports.userId) ?? '';
      if (userId.isEmpty || metadata.containsKey(userId)) {
        continue;
      }
      final report = _monthlyReportFromRow(row);
      if (report == null) {
        continue;
      }
      metadata[userId] = _UserMetadata(
        name: report.displayName,
        ruleNames: report.baseInfo.groupName.isEmpty
            ? '--'
            : report.baseInfo.groupName,
        departments: report.baseInfo.departmentsName.isEmpty
            ? '--'
            : report.baseInfo.departmentsName,
      );
    }
    return metadata;
  }

  MonthlyReport? _monthlyReportFromRow(RowMap row) {
    final rawJson = row.read(tables.monthlyReports.reportJson) ?? '';
    if (rawJson.isEmpty) {
      return null;
    }
    final data = jsonDecode(rawJson);
    return data is Map
        ? MonthlyReport.fromJson(Map<String, dynamic>.from(data))
        : null;
  }

  CheckinRecord _checkinFromRow(RowMap row) {
    final time = DateTime.fromMillisecondsSinceEpoch(
      _intValue(row.raw['checkin_at']),
    );
    final scheduleTime = row.raw['schedule_checkin_at'];
    return CheckinRecord(
      userId: row.raw['user_id']?.toString() ?? '',
      groupName: row.raw['group_name']?.toString() ?? '',
      checkinType: row.raw['checkin_type']?.toString() ?? '',
      exceptionType: row.raw['exception_type']?.toString() ?? '',
      checkinTime: time,
      locationTitle: row.raw['location_title']?.toString() ?? '',
      locationDetail: row.raw['location_detail']?.toString() ?? '',
      wifiName: row.raw['wifi_name']?.toString() ?? '',
      notes: row.raw['notes']?.toString() ?? '',
      wifiMac: row.raw['wifi_mac']?.toString() ?? '',
      mediaIds:
          tables.checkins.mediaIds.decode(row.raw['media_ids']) ?? const [],
      latitude: _nullableDouble(row.raw['latitude']),
      longitude: _nullableDouble(row.raw['longitude']),
      deviceId: row.raw['device_id']?.toString() ?? '',
      scheduleCheckinTime: scheduleTime == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(_intValue(scheduleTime)),
      groupId: _nullableInt(row.raw['group_id']),
      scheduleId: _nullableInt(row.raw['schedule_id']),
      timelineId: _nullableInt(row.raw['timeline_id']),
    );
  }

  Condition _checkinFilter({
    required DateTime startDate,
    required DateTime endDate,
    required Set<String> userIds,
    required CheckinDataType dataType,
  }) {
    return and([
      _atLeastDate(tables.checkins.recordDate, startDate),
      _atMostDate(tables.checkins.recordDate, endDate),
      if (userIds.isNotEmpty)
        inArray(tables.checkins.userId, userIds.toList(growable: false)),
      switch (dataType) {
        CheckinDataType.clockIn => _notLike(
          tables.checkins.checkinType,
          '%外出%',
        ),
        CheckinDataType.outside => like(tables.checkins.checkinType, '%外出%'),
        CheckinDataType.all => const Condition('1 = 1'),
      },
    ]);
  }
}

enum _SummaryPeriod { year, month, all }

class _DailyColumns {
  final userId = _CteColumnRef<String>('attendance_daily', 'user_id');
  final recordDate = _CteColumnRef<DateTime>('attendance_daily', 'record_date');
  final period = _CteColumnRef<String>('attendance_daily', 'period');
  final groupName = _CteColumnRef<String>('attendance_daily', 'group_name');
  final recordCount = _CteColumnRef<int>('attendance_daily', 'record_count');
  final workCount = _CteColumnRef<int>('attendance_daily', 'work_count');
  final attendedDay = _CteColumnRef<int>('attendance_daily', 'attended_day');
  final firstWorkAt = _CteColumnRef<int>('attendance_daily', 'first_work_at');
  final lastWorkAt = _CteColumnRef<int>('attendance_daily', 'last_work_at');
  final exceptionCount = _CteColumnRef<int>(
    'attendance_daily',
    'exception_count',
  );
  final timeExceptionCount = _CteColumnRef<int>(
    'attendance_daily',
    'time_exception_count',
  );
  final notCheckedCount = _CteColumnRef<int>(
    'attendance_daily',
    'not_checked_count',
  );
  final wifiExceptionCount = _CteColumnRef<int>(
    'attendance_daily',
    'wifi_exception_count',
  );
  final locationCount = _CteColumnRef<int>(
    'attendance_daily',
    'location_count',
  );
  final deviceCount = _CteColumnRef<int>('attendance_daily', 'device_count');
}

class _CteColumnRef<T> extends ColumnRef<T> {
  const _CteColumnRef(this.table, this.column);

  @override
  final String table;

  @override
  final String column;

  @override
  Object? encode(T? value) => value;

  @override
  T? decode(Object? raw) => raw as T?;
}

class _UserMetadata {
  const _UserMetadata({
    required this.name,
    required this.ruleNames,
    required this.departments,
  });

  final String name;
  final String ruleNames;
  final String departments;
}

Condition _atLeastDate(ColumnRef<DateTime> column, DateTime value) =>
    Condition('${column.toSqlIdentifier()} >= ?', [column.encode(value)]);

Condition _atMostDate(ColumnRef<DateTime> column, DateTime value) =>
    Condition('${column.toSqlIdentifier()} <= ?', [column.encode(value)]);

Condition _beforeDate(ColumnRef<DateTime> column, DateTime value) =>
    Condition('${column.toSqlIdentifier()} < ?', [column.encode(value)]);

Condition _atLeastInt(ColumnRef<int> column, int value) =>
    Condition('${column.toSqlIdentifier()} >= ?', [value]);

Condition _atMostInt(ColumnRef<int> column, int value) =>
    Condition('${column.toSqlIdentifier()} <= ?', [value]);

Condition _lessThanInt(ColumnRef<int> column, int value) =>
    Condition('${column.toSqlIdentifier()} < ?', [value]);

Condition _notLike(ColumnRef<String> column, String pattern) =>
    Condition('${column.toSqlIdentifier()} NOT LIKE ?', [pattern]);

SqlExpression _conditionalSum(String predicate) =>
    SqlExpression('SUM(CASE WHEN $predicate THEN 1 ELSE 0 END)');

SqlExpression _sumOf(ColumnRef<int> column) =>
    SqlExpression('SUM(${column.toSqlIdentifier()})');

SqlExpression expression(String sql) => SqlExpression(sql);

ColumnValue<Object?> nullableValue<T>(Column<T> column, T? value) =>
    ColumnValue<Object?>(column, value);

int _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _nullableInt(Object? value) => value == null ? null : _intValue(value);

double _doubleValue(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

double? _nullableDouble(Object? value) =>
    value == null ? null : _doubleValue(value);

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _monthKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}';
