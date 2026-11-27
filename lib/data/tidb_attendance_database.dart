import 'dart:convert';
import 'dart:io' show SecurityContext;

import 'package:dartonic_core/dartonic_core.dart';
import 'package:mysql1/mysql1.dart';

import '../config/database_config.dart';
import 'attendance_database.dart';
import 'attendance_summary.dart';
import 'checkin_record.dart';
import 'connection_status.dart';
import 'monthly_report.dart';
import 'orm/attendance_orm_store.dart';
import 'orm/attendance_schema.dart';
import 'orm/mysql_dartonic_driver.dart';

class TiDbAttendanceDatabase extends AttendanceDatabase {
  TiDbAttendanceDatabase({required this.config});

  final DatabaseConfig config;
  MySqlConnection? _connection;
  AttendanceOrmStore? _store;
  Future<AttendanceOrmStore>? _initialization;

  @override
  String get storageLabel => '数据库';

  @override
  String get storageEndpoint =>
      '${config.host}:${config.port}/${config.database}';

  @override
  Future<ConnectionStatus> checkConnection() async {
    final startedAt = DateTime.now();
    try {
      await (await _orm).ping();
      return ConnectionStatus(
        connected: true,
        message: '数据库连接正常',
        checkedAt: startedAt,
        latency: DateTime.now().difference(startedAt),
      );
    } catch (error) {
      return ConnectionStatus(
        connected: false,
        message: '数据库连接失败：$error',
        checkedAt: startedAt,
      );
    }
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
    return (await _orm).loadCheckinRecords(
      startDate: startDate,
      endDate: endDate,
      userIds: userIds,
      dataType: dataType,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<int> saveCheckinRecords(Iterable<CheckinRecord> records) async {
    return (await _orm).saveCheckinRecords(records);
  }

  @override
  Future<int> replaceCheckinRecords(
    Iterable<CheckinRecord> records, {
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    required Iterable<String> userIds,
  }) async {
    return (await _orm).replaceCheckinRecords(
      records,
      periodStart: periodStart,
      periodEndExclusive: periodEndExclusive,
      userIds: userIds,
    );
  }

  @override
  Future<int> saveMonthlyReports(
    Iterable<MonthlyReport> reports, {
    required int year,
    required DateTime periodStart,
    required DateTime periodEndExclusive,
  }) async {
    return (await _orm).saveMonthlyReports(
      reports,
      year: year,
      periodStart: periodStart,
      periodEndExclusive: periodEndExclusive,
    );
  }

  @override
  Future<int> replaceMonthlyReports(
    Iterable<MonthlyReport> reports, {
    required int year,
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    required Iterable<String> userIds,
  }) async {
    return (await _orm).replaceMonthlyReports(
      reports,
      year: year,
      periodStart: periodStart,
      periodEndExclusive: periodEndExclusive,
      userIds: userIds,
    );
  }

  @override
  Future<Set<String>> loadSyncedWindowKeys({
    required DateTime firstMonth,
    required DateTime lastMonth,
    required Set<String> userIds,
  }) async {
    return (await _orm).loadSyncedWindowKeys(
      firstMonth: firstMonth,
      lastMonth: lastMonth,
      userIds: userIds,
    );
  }

  @override
  Future<void> markSyncWindows({
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    required Iterable<String> userIds,
  }) async {
    return (await _orm).markSyncWindows(
      periodStart: periodStart,
      periodEndExclusive: periodEndExclusive,
      userIds: userIds,
    );
  }

  @override
  Future<AttendanceDatabaseStats> loadStats() async {
    return (await _orm).loadStats();
  }

  @override
  Future<int> startSyncRun({
    required DateTime firstMonth,
    required DateTime lastMonth,
    required int userCount,
    required AttendanceSyncMode mode,
  }) async {
    return (await _orm).startSyncRun(
      firstMonth: firstMonth,
      lastMonth: lastMonth,
      userCount: userCount,
      mode: mode,
    );
  }

  @override
  Future<void> finishSyncRun(
    int id, {
    required bool succeeded,
    required int recordCount,
    required int reportCount,
    String? errorMessage,
  }) async {
    return (await _orm).finishSyncRun(
      id,
      succeeded: succeeded,
      recordCount: recordCount,
      reportCount: reportCount,
      errorMessage: errorMessage,
    );
  }

  @override
  Future<AttendanceDateBounds?> loadCheckinDateBounds({
    Set<String> userIds = const {},
  }) async {
    return (await _orm).loadCheckinDateBounds(userIds: userIds);
  }

  @override
  Future<DateTime?> loadLatestCheckinTime() async {
    return (await _orm).loadLatestCheckinTime();
  }

  @override
  Future<DateTime?> loadLatestMonthlyReportTime() async {
    return (await _orm).loadLatestMonthlyReportTime();
  }

  @override
  Future<List<AttendanceSummaryRow>> loadRawYearSummary({
    required int firstYear,
    required int lastYear,
    Set<String> userIds = const {},
  }) async {
    return (await _orm).loadRawYearSummary(
      firstYear: firstYear,
      lastYear: lastYear,
      userIds: userIds,
    );
  }

  @override
  Future<List<AttendanceSummaryRow>> loadRawMonthlySummary({
    required DateTime firstMonth,
    required DateTime lastMonth,
    Set<String> userIds = const {},
  }) async {
    return (await _orm).loadRawMonthlySummary(
      firstMonth: firstMonth,
      lastMonth: lastMonth,
      userIds: userIds,
    );
  }

  @override
  Future<List<AttendanceSummaryRow>> loadRawAllTimeSummary({
    required DateTime startDate,
    required DateTime endDate,
    Set<String> userIds = const {},
  }) async {
    return (await _orm).loadRawAllTimeSummary(
      startDate: startDate,
      endDate: endDate,
      userIds: userIds,
    );
  }

  @override
  Future<List<AttendanceSummaryRow>> loadSummary({
    required int firstYear,
    required int lastYear,
    Set<String> userIds = const {},
  }) async {
    return (await _orm).loadSummary(
      firstYear: firstYear,
      lastYear: lastYear,
      userIds: userIds,
    );
  }

  @override
  Future<List<AttendanceSummaryRow>> loadMonthlySummary({
    required DateTime firstMonth,
    required DateTime lastMonth,
    Set<String> userIds = const {},
  }) async {
    return (await _orm).loadMonthlySummary(
      firstMonth: firstMonth,
      lastMonth: lastMonth,
      userIds: userIds,
    );
  }

  @override
  Future<MonthlyReport?> loadMonthlyReport({
    required String userId,
    required DateTime month,
  }) async {
    return (await _orm).loadMonthlyReport(userId: userId, month: month);
  }

  @override
  Future<List<MonthlyReportRecord>> loadMonthlyReports({
    required DateTime firstMonth,
    required DateTime lastMonth,
    Set<String> userIds = const {},
  }) async {
    return (await _orm).loadMonthlyReports(
      firstMonth: firstMonth,
      lastMonth: lastMonth,
      userIds: userIds,
    );
  }

  @override
  Future<List<AttendanceSummaryRow>> loadAllTimeSummary({
    required DateTime firstMonth,
    required DateTime lastMonth,
    Set<String> userIds = const {},
  }) async {
    return (await _orm).loadAllTimeSummary(
      firstMonth: firstMonth,
      lastMonth: lastMonth,
      userIds: userIds,
    );
  }

  @override
  Future<List<AttendanceSummaryRow>> loadDailyCheckinSummary({
    required DateTime startDate,
    required DateTime endDate,
    Set<String> userIds = const {},
  }) async {
    return (await _orm).loadDailyCheckinSummary(
      startDate: startDate,
      endDate: endDate,
      userIds: userIds,
    );
  }

  @override
  Future<Set<String>> loadSyncedSnapshotKeys({
    required DateTime firstMonth,
    required DateTime lastMonth,
    required Set<String> userIds,
  }) async {
    return (await _orm).loadSyncedSnapshotKeys(
      firstMonth: firstMonth,
      lastMonth: lastMonth,
      userIds: userIds,
    );
  }

  @override
  Future<void> close() async {
    _initialization = null;
    _store = null;
    final connection = _connection;
    _connection = null;
    await connection?.close();
  }

  Future<AttendanceOrmStore> get _orm async {
    final store = _store;
    if (store != null) {
      return store;
    }
    final opening = _initialization ??= _initializeOrm();
    try {
      final resolved = await opening;
      _store = resolved;
      return resolved;
    } catch (_) {
      _initialization = null;
      _store = null;
      final connection = _connection;
      _connection = null;
      await connection?.close();
      rethrow;
    }
  }

  Future<AttendanceOrmStore> _initializeOrm() async {
    if (!config.isConfigured) {
      throw StateError('数据库配置不完整，缺少：${config.missingFields.join('、')}');
    }
    final securityContext = config.sslCaPem.trim().isEmpty
        ? null
        : (SecurityContext(withTrustedRoots: false)
            ..setTrustedCertificatesBytes(utf8.encode(config.sslCaPem)));
    final connection = await MySqlConnection.connect(
      ConnectionSettings(
        host: config.host,
        port: config.port,
        user: config.username,
        password: config.password,
        db: config.database,
        useSSL: config.useSSL,
        securityContext: securityContext,
        timeout: config.connectTimeout,
      ),
    );
    _connection = connection;
    await _createSchema(connection);
    final driver = MysqlDartonicDriver(connection);
    await driver.connect();
    final tables = AttendanceOrmTables();
    final database = DartonicDb(
      driver: driver,
      schemas: tables.all,
      dialect: Dialect.mysql,
    );
    return AttendanceOrmStore(database: database, tables: tables);
  }

  /// Bootstrap only. All application reads and writes use the ORM store.
  Future<void> _createSchema(MySqlConnection connection) async {
    await connection.query('''
CREATE TABLE IF NOT EXISTS checkin_records (
  source_key VARCHAR(512) PRIMARY KEY,
  user_id VARCHAR(191) NOT NULL,
  record_date DATE NOT NULL,
  checkin_at BIGINT NOT NULL,
  checkin_type VARCHAR(64) NOT NULL DEFAULT '',
  exception_type VARCHAR(255) NOT NULL DEFAULT '',
  group_name VARCHAR(255) NOT NULL DEFAULT '',
  group_id BIGINT NULL,
  schedule_id BIGINT NULL,
  timeline_id BIGINT NULL,
  location_title VARCHAR(512) NOT NULL DEFAULT '',
  location_detail VARCHAR(1024) NOT NULL DEFAULT '',
  wifi_name VARCHAR(255) NOT NULL DEFAULT '',
  wifi_mac VARCHAR(128) NOT NULL DEFAULT '',
  notes TEXT NULL,
  device_id VARCHAR(255) NOT NULL DEFAULT '',
  schedule_checkin_at BIGINT NULL,
  latitude DOUBLE NULL,
  longitude DOUBLE NULL,
  media_ids JSON NULL,
  synced_at BIGINT NOT NULL,
  INDEX idx_checkin_user_date (user_id, record_date),
  INDEX idx_checkin_time (checkin_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
''');
    await connection.query('''
CREATE TABLE IF NOT EXISTS sync_runs (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  started_at BIGINT NOT NULL,
  completed_at BIGINT NULL,
  first_month VARCHAR(16) NOT NULL,
  last_month VARCHAR(16) NOT NULL,
  user_count INT NOT NULL,
  sync_mode VARCHAR(16) NOT NULL,
  status VARCHAR(16) NOT NULL,
  record_count INT NOT NULL DEFAULT 0,
  report_count INT NOT NULL DEFAULT 0,
  error_message TEXT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
''');
    await connection.query('''
CREATE TABLE IF NOT EXISTS sync_windows (
  source_key VARCHAR(255) PRIMARY KEY,
  user_id VARCHAR(191) NOT NULL,
  period_start BIGINT NOT NULL,
  period_end_exclusive BIGINT NOT NULL,
  synced_at BIGINT NOT NULL,
  INDEX idx_sync_window_period (period_start, period_end_exclusive)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
''');
    await connection.query('''
CREATE TABLE IF NOT EXISTS monthly_report_snapshots (
  source_key VARCHAR(512) PRIMARY KEY,
  user_id VARCHAR(191) NOT NULL,
  year INT NOT NULL,
  period_start BIGINT NOT NULL,
  period_end_exclusive BIGINT NOT NULL,
  report_json TEXT NOT NULL,
  synced_at BIGINT NOT NULL,
  INDEX idx_report_year_user (year, user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
''');
  }
}
