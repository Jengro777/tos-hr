import '../config/database_config.dart';
import 'attendance_database.dart';
import 'attendance_summary.dart';
import 'checkin_record.dart';
import 'cloudflare_attendance_database.dart';
import 'connection_status.dart';

class UnsupportedAttendanceDatabase extends AttendanceDatabase {
  @override
  Future<ConnectionStatus> checkConnection() async {
    return ConnectionStatus(
      connected: false,
      message: 'Web 端不支持直连数据库，请使用服务端代理',
      checkedAt: DateTime.now(),
    );
  }

  @override
  Future<AttendanceDatabaseStats> loadStats() => _unsupported();

  @override
  Future<CheckinRecordPage> loadCheckinRecords({
    required DateTime startDate,
    required DateTime endDate,
    required Set<String> userIds,
    required CheckinDataType dataType,
    int limit = 200,
    int offset = 0,
  }) => _unsupported();

  @override
  Future<int> saveCheckinRecords(Iterable<CheckinRecord> records) =>
      _unsupported();

  @override
  Future<int> replaceCheckinRecords(
    Iterable<CheckinRecord> records, {
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    required Iterable<String> userIds,
  }) => _unsupported();

  @override
  Future<Set<String>> loadSyncedWindowKeys({
    required DateTime firstMonth,
    required DateTime lastMonth,
    required Set<String> userIds,
  }) => _unsupported();

  @override
  Future<void> markSyncWindows({
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    required Iterable<String> userIds,
  }) => _unsupported();

  @override
  Future<AttendanceDateBounds?> loadCheckinDateBounds({
    Set<String> userIds = const {},
  }) => _unsupported();

  @override
  Future<DateTime?> loadLatestCheckinTime() => _unsupported();

  @override
  Future<List<AttendanceSummaryRow>> loadRawYearSummary({
    required int firstYear,
    required int lastYear,
    Set<String> userIds = const {},
  }) => _unsupported();

  @override
  Future<List<AttendanceSummaryRow>> loadRawMonthlySummary({
    required DateTime firstMonth,
    required DateTime lastMonth,
    Set<String> userIds = const {},
  }) => _unsupported();

  @override
  Future<List<AttendanceSummaryRow>> loadRawAllTimeSummary({
    required DateTime startDate,
    required DateTime endDate,
    Set<String> userIds = const {},
  }) => _unsupported();

  @override
  Future<int> startSyncRun({
    required DateTime firstMonth,
    required DateTime lastMonth,
    required int userCount,
    required AttendanceSyncMode mode,
  }) => _unsupported();

  @override
  Future<void> finishSyncRun(
    int id, {
    required bool succeeded,
    required int recordCount,
    required int reportCount,
    String? errorMessage,
  }) => _unsupported();

  Future<T> _unsupported<T>() {
    return Future<T>.error(
      UnsupportedError('Flutter Web 不支持直接连接数据库，请使用服务端代理。'),
    );
  }

  @override
  Future<void> close() async {}
}

AttendanceDatabase createAttendanceDatabase(DatabaseConfig? config) {
  if (config?.proxyEnabled == true) {
    return CloudflareAttendanceDatabase(config: config!);
  }
  return UnsupportedAttendanceDatabase();
}
