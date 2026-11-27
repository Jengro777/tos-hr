import 'package:dartonic_core/dartonic_core.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common/sqlite_api.dart' as sqlite_api;

import 'attendance_storage.dart';
import 'attendance_summary.dart';
import 'checkin_record.dart';
import 'connection_status.dart';
import 'monthly_report.dart';
import 'orm/attendance_orm_store.dart';
import 'orm/attendance_schema.dart';
import 'orm/sqflite_dartonic_driver.dart';

export 'attendance_storage.dart';

class AttendanceDatabase {
  AttendanceDatabase({
    sqlite_api.DatabaseFactory? factory,
    this.databasePath,
    this.databaseName = 'tospino_hr.db',
  }) : _factoryOverride = factory;

  final sqlite_api.DatabaseFactory? _factoryOverride;
  final String databaseName;
  final String? databasePath;
  Future<sqlite_api.Database>? _openingDatabase;
  Future<AttendanceOrmStore>? _openingStore;
  AttendanceOrmStore? _store;

  String get storageLabel => 'SQLite 测试库';
  String get storageEndpoint => 'local';

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

  sqlite_api.DatabaseFactory get _factory =>
      _factoryOverride ?? sqflite.databaseFactory;

  Future<sqlite_api.Database> get database =>
      _openingDatabase ??= _openDatabase();

  AttendanceDatabase createInMemoryCopy() {
    return AttendanceDatabase(
      factory: _factory,
      databasePath: sqflite.inMemoryDatabasePath,
    );
  }

  Future<AttendanceOrmStore> get _orm async {
    final store = _store;
    if (store != null) {
      return store;
    }
    final opening = _openingStore ??= _openOrm();
    final resolved = await opening;
    _store = resolved;
    return resolved;
  }

  Future<sqlite_api.Database> _openDatabase() async {
    final resolvedPath =
        databasePath ?? path.join(await _databasesPath, databaseName);
    return _factory.openDatabase(resolvedPath);
  }

  Future<String> get _databasesPath => sqflite.getDatabasesPath();

  Future<AttendanceOrmStore> _openOrm() async {
    final sqliteDatabase = await database;
    final tables = AttendanceOrmTables();
    final ormDatabase = DartonicDb(
      driver: SqfliteDartonicDriver(sqliteDatabase),
      schemas: tables.all,
      dialect: Dialect.sqlite,
    );
    await ormDatabase.sync();
    return AttendanceOrmStore(database: ormDatabase, tables: tables);
  }

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

  Future<int> saveCheckinRecords(Iterable<CheckinRecord> records) async {
    return (await _orm).saveCheckinRecords(records);
  }

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

  Future<AttendanceDateBounds?> loadCheckinDateBounds({
    Set<String> userIds = const {},
  }) async {
    return (await _orm).loadCheckinDateBounds(userIds: userIds);
  }

  Future<DateTime?> loadLatestCheckinTime() async {
    return (await _orm).loadLatestCheckinTime();
  }

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

  Future<AttendanceDatabaseStats> loadStats() async {
    return (await _orm).loadStats();
  }

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

  Future<void> close() async {
    _openingStore = null;
    _store = null;
    final opening = _openingDatabase;
    if (opening != null) {
      final database = await opening;
      await database.close();
    }
    _openingDatabase = null;
  }
}
