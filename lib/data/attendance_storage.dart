import 'checkin_record.dart';

enum AttendanceSyncMode { full, incremental }

enum AttendanceSyncDataset { checkins, reports, all }

extension AttendanceSyncDatasetInfo on AttendanceSyncDataset {
  bool get includesCheckins => this != AttendanceSyncDataset.reports;

  bool get includesReports => this != AttendanceSyncDataset.checkins;

  String get label => switch (this) {
    AttendanceSyncDataset.checkins => '打卡记录',
    AttendanceSyncDataset.reports => '月报',
    AttendanceSyncDataset.all => '打卡记录与月报',
  };
}

class AttendanceDateBounds {
  const AttendanceDateBounds({required this.firstDate, required this.lastDate});

  final DateTime firstDate;
  final DateTime lastDate;
}

class CheckinRecordPage {
  const CheckinRecordPage({
    required this.records,
    required this.totalCount,
    required this.totalUserCount,
    required this.totalExceptionCount,
  });

  final List<CheckinRecord> records;
  final int totalCount;
  final int totalUserCount;
  final int totalExceptionCount;
}

class AttendanceDatabaseStats {
  const AttendanceDatabaseStats({
    required this.checkinRecordCount,
    required this.monthlyReportCount,
    this.attendanceDateCount = 0,
    this.lastRun,
  });

  final int checkinRecordCount;
  final int monthlyReportCount;
  final int attendanceDateCount;
  final AttendanceSyncRun? lastRun;
}

class AttendanceSyncRun {
  const AttendanceSyncRun({
    required this.id,
    required this.startedAt,
    required this.firstMonth,
    required this.lastMonth,
    required this.userCount,
    required this.syncMode,
    required this.status,
    required this.recordCount,
    required this.reportCount,
    this.completedAt,
    this.errorMessage,
  });

  factory AttendanceSyncRun.fromMap(Map<String, Object?> map) {
    return AttendanceSyncRun(
      id: _intValue(map['id']),
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        _intValue(map['started_at']),
      ),
      completedAt: map['completed_at'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['completed_at']! as num).toInt(),
            )
          : null,
      firstMonth: map['first_month']?.toString() ?? '',
      lastMonth: map['last_month']?.toString() ?? '',
      userCount: _intValue(map['user_count']),
      syncMode: map['sync_mode']?.toString() ?? 'full',
      status: map['status']?.toString() ?? '',
      recordCount: _intValue(map['record_count']),
      reportCount: _intValue(map['report_count']),
      errorMessage: map['error_message']?.toString(),
    );
  }

  final int id;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String firstMonth;
  final String lastMonth;
  final int userCount;
  final String syncMode;
  final String status;
  final int recordCount;
  final int reportCount;
  final String? errorMessage;

  bool get succeeded => status == 'completed';
}

int _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
