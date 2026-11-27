import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/database_config.dart';
import 'attendance_database.dart';
import 'attendance_summary.dart';
import 'checkin_record.dart';
import 'connection_status.dart';
import 'monthly_report.dart';

class CloudflareAttendanceDatabase extends AttendanceDatabase {
  CloudflareAttendanceDatabase({required this.config, http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final DatabaseConfig config;
  final http.Client _httpClient;

  @override
  String get storageLabel => 'Cloudflare + TiDB';

  @override
  String get storageEndpoint =>
      '${config.host}/${config.database} · Cloudflare 代理';

  Uri get _endpoint => Uri.base.resolve('/api/db');

  @override
  Future<ConnectionStatus> checkConnection() async {
    final startedAt = DateTime.now();
    try {
      await _post('ping');
      return ConnectionStatus(
        connected: true,
        message: 'Cloudflare 与 TiDB 连接正常',
        checkedAt: startedAt,
        latency: DateTime.now().difference(startedAt),
      );
    } catch (error) {
      return ConnectionStatus(
        connected: false,
        message: 'TiDB 连接失败：$error',
        checkedAt: startedAt,
      );
    }
  }

  @override
  Future<AttendanceDatabaseStats> loadStats() async {
    final data = _map(await _post('load_stats'));
    final lastRun = data['last_run'];
    return AttendanceDatabaseStats(
      checkinRecordCount: _int(data['checkin_record_count']),
      monthlyReportCount: _int(data['monthly_report_count']),
      attendanceDateCount: _int(data['attendance_date_count']),
      lastRun: lastRun is Map
          ? AttendanceSyncRun.fromMap(Map<String, Object?>.from(lastRun))
          : null,
    );
  }

  @override
  Future<CheckinRecordPage> loadCheckinRecords({
    required DateTime startDate,
    required DateTime endDate,
    required Set<String> userIds,
    required CheckinDataType dataType,
    int limit = 200,
    int offset = 0,
  }) async {
    final data = _map(
      await _post('load_checkin_page', {
        'start_date': _dateKey(startDate),
        'end_date': _dateKey(endDate),
        'user_ids': userIds.toList(growable: false),
        'data_type': dataType.apiValue,
        'limit': limit,
        'offset': offset,
      }),
    );
    final records = data['records'];
    return CheckinRecordPage(
      records: records is List
          ? records
                .whereType<Map>()
                .map(
                  (record) =>
                      CheckinRecord.fromJson(Map<String, dynamic>.from(record)),
                )
                .toList(growable: false)
          : const [],
      totalCount: _int(data['total_count']),
      totalUserCount: _int(data['total_user_count']),
      totalExceptionCount: _int(data['total_exception_count']),
    );
  }

  @override
  Future<int> saveCheckinRecords(Iterable<CheckinRecord> records) async {
    final data = _map(
      await _post('save_checkins', {
        'records': records.map(_recordToJson).toList(growable: false),
      }),
    );
    return _int(data['count']);
  }

  @override
  Future<int> replaceCheckinRecords(
    Iterable<CheckinRecord> records, {
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    required Iterable<String> userIds,
  }) async {
    final data = _map(
      await _post('replace_checkins', {
        'records': records.map(_recordToJson).toList(growable: false),
        'period_start_date': _dateKey(periodStart),
        'period_end_date': _dateKey(periodEndExclusive),
        'user_ids': userIds.toList(growable: false),
      }),
    );
    return _int(data['count']);
  }

  @override
  Future<int> saveMonthlyReports(
    Iterable<MonthlyReport> reports, {
    required int year,
    required DateTime periodStart,
    required DateTime periodEndExclusive,
  }) async {
    final data = _map(
      await _post('save_monthly_reports', {
        ..._monthlyReportPayload(
          reports,
          year: year,
          periodStart: periodStart,
          periodEndExclusive: periodEndExclusive,
        ),
      }),
    );
    return _int(data['count']);
  }

  @override
  Future<int> replaceMonthlyReports(
    Iterable<MonthlyReport> reports, {
    required int year,
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    required Iterable<String> userIds,
  }) async {
    final data = _map(
      await _post('replace_monthly_reports', {
        ..._monthlyReportPayload(
          reports,
          year: year,
          periodStart: periodStart,
          periodEndExclusive: periodEndExclusive,
        ),
        'user_ids': userIds.toList(growable: false),
      }),
    );
    return _int(data['count']);
  }

  @override
  Future<Set<String>> loadSyncedWindowKeys({
    required DateTime firstMonth,
    required DateTime lastMonth,
    required Set<String> userIds,
  }) async {
    final data = await _post('load_synced_window_keys', {
      'first_month_ms': DateTime(
        firstMonth.year,
        firstMonth.month,
      ).millisecondsSinceEpoch,
      'last_month_end_ms': DateTime(
        lastMonth.year,
        lastMonth.month + 1,
      ).millisecondsSinceEpoch,
      'user_ids': userIds.toList(growable: false),
    });
    return data is List ? data.map((value) => '$value').toSet() : <String>{};
  }

  @override
  Future<Set<String>> loadSyncedSnapshotKeys({
    required DateTime firstMonth,
    required DateTime lastMonth,
    required Set<String> userIds,
  }) async {
    final data = await _post('load_report_snapshot_keys', {
      'first_month_ms': DateTime(
        firstMonth.year,
        firstMonth.month,
      ).millisecondsSinceEpoch,
      'last_month_end_ms': DateTime(
        lastMonth.year,
        lastMonth.month + 1,
      ).millisecondsSinceEpoch,
      'user_ids': userIds.toList(growable: false),
    });
    return data is List ? data.map((value) => '$value').toSet() : <String>{};
  }

  @override
  Future<void> markSyncWindows({
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    required Iterable<String> userIds,
  }) async {
    await _post('mark_sync_windows', {
      'period_start_ms': periodStart.millisecondsSinceEpoch,
      'period_end_exclusive_ms': periodEndExclusive.millisecondsSinceEpoch,
      'user_ids': userIds.toList(growable: false),
    });
  }

  @override
  Future<int> startSyncRun({
    required DateTime firstMonth,
    required DateTime lastMonth,
    required int userCount,
    required AttendanceSyncMode mode,
  }) async {
    final data = _map(
      await _post('start_sync_run', {
        'first_month': _monthKey(firstMonth),
        'last_month': _monthKey(lastMonth),
        'user_count': userCount,
        'mode': mode.name,
      }),
    );
    return _int(data['id']);
  }

  @override
  Future<void> finishSyncRun(
    int id, {
    required bool succeeded,
    required int recordCount,
    required int reportCount,
    String? errorMessage,
  }) async {
    await _post('finish_sync_run', {
      'id': id,
      'succeeded': succeeded,
      'record_count': recordCount,
      'report_count': reportCount,
      'error_message': errorMessage,
    });
  }

  @override
  Future<AttendanceDateBounds?> loadCheckinDateBounds({
    Set<String> userIds = const {},
  }) async {
    final data = await _post('load_date_bounds', {
      'user_ids': userIds.toList(growable: false),
    });
    if (data is! Map ||
        data['first_date'] == null ||
        data['last_date'] == null) {
      return null;
    }
    return AttendanceDateBounds(
      firstDate: DateTime.parse('${data['first_date']}'),
      lastDate: DateTime.parse('${data['last_date']}'),
    );
  }

  @override
  Future<DateTime?> loadLatestCheckinTime() async {
    final data = await _post('load_latest_checkin_time');
    if (data is! Map || data['milliseconds'] == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(_int(data['milliseconds']));
  }

  @override
  Future<DateTime?> loadLatestMonthlyReportTime() async {
    final data = await _post('load_latest_monthly_report_time');
    if (data is! Map || data['milliseconds'] == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(_int(data['milliseconds']));
  }

  @override
  Future<List<AttendanceSummaryRow>> loadRawYearSummary({
    required int firstYear,
    required int lastYear,
    Set<String> userIds = const {},
  }) async {
    return _summaryRows('load_raw_year_summary', {
      'start_date': _dateKey(DateTime(firstYear)),
      'end_date': _dateKey(DateTime(lastYear, 12, 31)),
      'user_ids': userIds.toList(growable: false),
    });
  }

  @override
  Future<List<AttendanceSummaryRow>> loadRawMonthlySummary({
    required DateTime firstMonth,
    required DateTime lastMonth,
    Set<String> userIds = const {},
  }) async {
    return _summaryRows('load_raw_month_summary', {
      'start_date': _dateKey(DateTime(firstMonth.year, firstMonth.month)),
      'end_date': _dateKey(
        DateTime(
          lastMonth.year,
          lastMonth.month + 1,
        ).subtract(const Duration(days: 1)),
      ),
      'user_ids': userIds.toList(growable: false),
    });
  }

  @override
  Future<List<AttendanceSummaryRow>> loadRawAllTimeSummary({
    required DateTime startDate,
    required DateTime endDate,
    Set<String> userIds = const {},
  }) async {
    return _summaryRows('load_raw_all_summary', {
      'start_date': _dateKey(startDate),
      'end_date': _dateKey(endDate),
      'user_ids': userIds.toList(growable: false),
    });
  }

  @override
  Future<List<AttendanceSummaryRow>> loadSummary({
    required int firstYear,
    required int lastYear,
    Set<String> userIds = const {},
  }) async {
    final reports = await _loadMonthlyReportSnapshots(
      start: DateTime(firstYear),
      endExclusive: DateTime(lastYear + 1),
      userIds: userIds,
    );
    final builder = AttendanceSummaryBuilder();
    for (final snapshot in reports) {
      builder.addReports([snapshot.report], year: snapshot.year);
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
        _withRawAttendance(row, rawByKey['${row.year}|${row.userId}']),
    ];
  }

  @override
  Future<List<AttendanceSummaryRow>> loadMonthlySummary({
    required DateTime firstMonth,
    required DateTime lastMonth,
    Set<String> userIds = const {},
  }) async {
    final reports = await _loadMonthlyReportSnapshots(
      start: DateTime(firstMonth.year, firstMonth.month),
      endExclusive: DateTime(lastMonth.year, lastMonth.month + 1),
      userIds: userIds,
    );
    final builder = AttendanceMonthlySummaryBuilder();
    for (final snapshot in reports) {
      builder.addReports(
        [snapshot.report],
        year: snapshot.periodStart.year,
        month: snapshot.periodStart.month,
      );
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
        _withRawAttendance(row, rawByKey['${row.periodLabel}|${row.userId}']),
    ];
  }

  @override
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
    final rawRows = await loadRawAllTimeSummary(
      startDate: DateTime(firstMonth.year, firstMonth.month),
      endDate: DateTime(
        lastMonth.year,
        lastMonth.month + 1,
      ).subtract(const Duration(days: 1)),
      userIds: userIds,
    );
    final rawByUser = {for (final row in rawRows) row.userId: row};
    return [
      for (final row in rows) _withRawAttendance(row, rawByUser[row.userId]),
    ];
  }

  @override
  Future<List<AttendanceSummaryRow>> loadDailyCheckinSummary({
    required DateTime startDate,
    required DateTime endDate,
    Set<String> userIds = const {},
  }) async {
    return _summaryRows('load_daily_summary', {
      'start_date': _dateKey(startDate),
      'end_date': _dateKey(endDate),
      'user_ids': userIds.toList(growable: false),
    });
  }

  AttendanceSummaryRow _withRawAttendance(
    AttendanceSummaryRow row,
    AttendanceSummaryRow? raw,
  ) {
    return row
        .withMetric(
          AttendanceMetric.checkinRecordCount,
          raw?.valueOf(AttendanceMetric.checkinRecordCount) ?? 0,
        )
        .withMetric(
          AttendanceMetric.attendanceDays,
          raw?.valueOf(AttendanceMetric.attendanceDays) ?? 0,
        );
  }

  Future<List<_CloudMonthlyReportSnapshot>> _loadMonthlyReportSnapshots({
    required DateTime start,
    required DateTime endExclusive,
    required Set<String> userIds,
  }) async {
    final data = await _post('load_monthly_report_snapshots', {
      'start_ms': start.millisecondsSinceEpoch,
      'end_exclusive_ms': endExclusive.millisecondsSinceEpoch,
      'user_ids': userIds.toList(growable: false),
    });
    if (data is! List) {
      return const [];
    }
    final snapshots = <_CloudMonthlyReportSnapshot>[];
    for (final item in data.whereType<Map>()) {
      final row = Map<String, dynamic>.from(item);
      final rawReport = row['report_json'];
      final decoded = rawReport is String ? jsonDecode(rawReport) : rawReport;
      if (decoded is! Map) {
        continue;
      }
      final periodStartMs = _int(row['period_start']);
      final periodStart = DateTime.fromMillisecondsSinceEpoch(periodStartMs);
      final parsedYear = _int(row['year']);
      snapshots.add(
        _CloudMonthlyReportSnapshot(
          year: parsedYear > 0 ? parsedYear : periodStart.year,
          periodStart: periodStart,
          report: MonthlyReport.fromJson(Map<String, dynamic>.from(decoded)),
        ),
      );
    }
    return snapshots;
  }

  Future<List<AttendanceSummaryRow>> _summaryRows(
    String operation,
    Map<String, Object?> payload,
  ) async {
    final data = await _post(operation, payload);
    if (data is! List) {
      return const [];
    }
    return data
        .whereType<Map>()
        .map((row) => _summaryFromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  AttendanceSummaryRow _summaryFromJson(Map<String, dynamic> json) {
    final metrics = _map(json['metrics']);
    return AttendanceSummaryRow(
      year: _int(json['year']),
      month: json['month'] == null ? null : _int(json['month']),
      periodLabelOverride: json['period_label']?.toString(),
      name: json['name']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      ruleNames: json['rule_names']?.toString() ?? '--',
      departments: json['departments']?.toString() ?? '--',
      sourceRecordCount: _int(json['source_record_count']),
      metrics: Map<AttendanceMetric, double>.unmodifiable({
        for (final metric in AttendanceMetric.values)
          metric: (metrics[metric.name] as num?)?.toDouble() ?? 0,
      }),
    );
  }

  Map<String, Object?> _recordToJson(CheckinRecord record) => {
    'source_key': record.sourceKey,
    'user_id': record.userId,
    'record_date': _dateKey(record.checkinTime),
    'checkin_at': record.checkinTime.millisecondsSinceEpoch,
    'checkin_type': record.checkinType,
    'exception_type': record.exceptionType,
    'group_name': record.groupName,
    'group_id': record.groupId,
    'schedule_id': record.scheduleId,
    'timeline_id': record.timelineId,
    'location_title': record.locationTitle,
    'location_detail': record.locationDetail,
    'wifi_name': record.wifiName,
    'wifi_mac': record.wifiMac,
    'notes': record.notes,
    'device_id': record.deviceId,
    'schedule_checkin_at': record.scheduleCheckinTime?.millisecondsSinceEpoch,
    'latitude': record.latitude,
    'longitude': record.longitude,
    'media_ids': record.mediaIds,
  };

  Map<String, Object?> _monthlyReportPayload(
    Iterable<MonthlyReport> reports, {
    required int year,
    required DateTime periodStart,
    required DateTime periodEndExclusive,
  }) {
    return {
      'year': year,
      'period_start_date': _dateKey(periodStart),
      'period_start_ms': periodStart.millisecondsSinceEpoch,
      'period_end_exclusive_ms': periodEndExclusive.millisecondsSinceEpoch,
      'reports': [
        for (final report in reports)
          {'user_id': report.userId, 'report_json': report.toJson()},
      ],
    };
  }

  Future<Object?> _post(
    String action, [
    Map<String, Object?> payload = const {},
  ]) async {
    final response = await _httpClient
        .post(
          _endpoint,
          headers: const {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({'action': action, 'payload': payload}),
        )
        .timeout(const Duration(seconds: 30));
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw StateError('Cloudflare API 返回了无法解析的数据');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map ? decoded['message'] : null;
      throw StateError(message?.toString() ?? 'HTTP ${response.statusCode}');
    }
    if (decoded is Map && decoded['success'] == false) {
      throw StateError(decoded['message']?.toString() ?? 'Cloudflare API 请求失败');
    }
    return decoded;
  }

  @override
  Future<void> close() async {
    _httpClient.close();
  }
}

class _CloudMonthlyReportSnapshot {
  const _CloudMonthlyReportSnapshot({
    required this.year,
    required this.periodStart,
    required this.report,
  });

  final int year;
  final DateTime periodStart;
  final MonthlyReport report;
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

int _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _monthKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}';
