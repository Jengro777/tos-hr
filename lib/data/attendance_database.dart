import 'attendance_storage.dart';
import 'attendance_summary.dart';
import 'checkin_record.dart';
import 'connection_status.dart';
import 'monthly_report.dart';

export 'attendance_storage.dart';

abstract class AttendanceDatabase {
  String get storageLabel => '数据库';

  String get storageEndpoint => '--';

  Future<ConnectionStatus> checkConnection() => _unsupported();

  Future<AttendanceDatabaseStats> loadStats() => _unsupported();

  Future<CheckinRecordPage> loadCheckinRecords({
    required DateTime startDate,
    required DateTime endDate,
    required Set<String> userIds,
    required CheckinDataType dataType,
    int limit = 200,
    int offset = 0,
  }) => _unsupported();

  Future<int> saveCheckinRecords(Iterable<CheckinRecord> records) =>
      _unsupported();

  Future<int> replaceCheckinRecords(
    Iterable<CheckinRecord> records, {
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    required Iterable<String> userIds,
  }) => _unsupported();

  Future<int> saveMonthlyReports(
    Iterable<MonthlyReport> reports, {
    required int year,
    required DateTime periodStart,
    required DateTime periodEndExclusive,
  }) => _unsupported();

  Future<int> replaceMonthlyReports(
    Iterable<MonthlyReport> reports, {
    required int year,
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    required Iterable<String> userIds,
  }) => _unsupported();

  Future<List<AttendanceSummaryRow>> loadSummary({
    required int firstYear,
    required int lastYear,
    Set<String> userIds = const {},
  }) => _unsupported();

  Future<List<AttendanceSummaryRow>> loadMonthlySummary({
    required DateTime firstMonth,
    required DateTime lastMonth,
    Set<String> userIds = const {},
  }) => _unsupported();

  Future<MonthlyReport?> loadMonthlyReport({
    required String userId,
    required DateTime month,
  }) => _unsupported();

  Future<List<MonthlyReportRecord>> loadMonthlyReports({
    required DateTime firstMonth,
    required DateTime lastMonth,
    Set<String> userIds = const {},
  }) => _unsupported();

  Future<List<AttendanceSummaryRow>> loadAllTimeSummary({
    required DateTime firstMonth,
    required DateTime lastMonth,
    Set<String> userIds = const {},
  }) => _unsupported();

  Future<List<AttendanceSummaryRow>> loadRawYearSummary({
    required int firstYear,
    required int lastYear,
    Set<String> userIds = const {},
  }) => _unsupported();

  Future<List<AttendanceSummaryRow>> loadRawMonthlySummary({
    required DateTime firstMonth,
    required DateTime lastMonth,
    Set<String> userIds = const {},
  }) => _unsupported();

  Future<List<AttendanceSummaryRow>> loadRawAllTimeSummary({
    required DateTime startDate,
    required DateTime endDate,
    Set<String> userIds = const {},
  }) => _unsupported();

  Future<List<AttendanceSummaryRow>> loadDailyCheckinSummary({
    required DateTime startDate,
    required DateTime endDate,
    Set<String> userIds = const {},
  }) => _unsupported();

  Future<Set<String>> loadSyncedSnapshotKeys({
    required DateTime firstMonth,
    required DateTime lastMonth,
    required Set<String> userIds,
  }) => _unsupported();

  Future<Set<String>> loadSyncedWindowKeys({
    required DateTime firstMonth,
    required DateTime lastMonth,
    required Set<String> userIds,
  }) => _unsupported();

  Future<void> markSyncWindows({
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    required Iterable<String> userIds,
  }) => _unsupported();

  Future<AttendanceDateBounds?> loadCheckinDateBounds({
    Set<String> userIds = const {},
  }) => _unsupported();

  Future<DateTime?> loadLatestCheckinTime() => _unsupported();

  Future<DateTime?> loadLatestMonthlyReportTime() => _unsupported();

  Future<int> startSyncRun({
    required DateTime firstMonth,
    required DateTime lastMonth,
    required int userCount,
    required AttendanceSyncMode mode,
  }) => _unsupported();

  Future<void> finishSyncRun(
    int id, {
    required bool succeeded,
    required int recordCount,
    required int reportCount,
    String? errorMessage,
  }) => _unsupported();

  Future<void> close() async {}

  Future<T> _unsupported<T>() {
    return Future<T>.error(UnsupportedError('当前运行环境没有可用的数据库连接'));
  }
}
