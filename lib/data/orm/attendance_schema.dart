import 'dart:convert';

import 'package:dartonic_core/dartonic_core.dart';

class AttendanceOrmTables {
  AttendanceOrmTables()
    : checkins = CheckinRecordsTable(),
      syncRuns = SyncRunsTable(),
      syncWindows = SyncWindowsTable(),
      monthlyReports = MonthlyReportSnapshotsTable();

  final CheckinRecordsTable checkins;
  final SyncRunsTable syncRuns;
  final SyncWindowsTable syncWindows;
  final MonthlyReportSnapshotsTable monthlyReports;

  List<Table> get all => [checkins, syncRuns, syncWindows, monthlyReports];
}

class CheckinRecordsTable extends Table {
  final sourceKey = varchar('source_key', length: 512).primaryKey();
  final userId = varchar('user_id', length: 191).notNull();
  final recordDate = attendanceDateColumn('record_date').notNull();
  final checkinAt = bigint('checkin_at').notNull();
  final checkinType = varchar(
    'checkin_type',
    length: 64,
  ).notNull().withDefault("''");
  final exceptionType = varchar(
    'exception_type',
    length: 255,
  ).notNull().withDefault("''");
  final groupName = varchar(
    'group_name',
    length: 255,
  ).notNull().withDefault("''");
  final groupId = bigint('group_id');
  final scheduleId = bigint('schedule_id');
  final timelineId = bigint('timeline_id');
  final locationTitle = varchar(
    'location_title',
    length: 512,
  ).notNull().withDefault("''");
  final locationDetail = varchar(
    'location_detail',
    length: 1024,
  ).notNull().withDefault("''");
  final wifiName = varchar(
    'wifi_name',
    length: 255,
  ).notNull().withDefault("''");
  final wifiMac = varchar('wifi_mac', length: 128).notNull().withDefault("''");
  final notes = text('notes');
  final deviceId = varchar(
    'device_id',
    length: 255,
  ).notNull().withDefault("''");
  final scheduleCheckinAt = bigint('schedule_checkin_at');
  final latitude = doubleColumn('latitude');
  final longitude = doubleColumn('longitude');
  final mediaIds = json<List<String>>(
    'media_ids',
    decoder: (raw) {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! List) {
        return const [];
      }
      return decoded.map((value) => value.toString()).toList(growable: false);
    },
    encoder: (value) => value,
  );
  final syncedAt = bigint('synced_at').notNull();

  @override
  String get tableName => 'checkin_records';

  @override
  List<Index> defineIndexes() => [
    index('idx_checkin_user_date').on([userId, recordDate]),
    index('idx_checkin_time').on([checkinAt]),
  ];
}

class SyncRunsTable extends Table {
  final id = integer('id').primaryKey(autoIncrement: true);
  final startedAt = bigint('started_at').notNull();
  final completedAt = bigint('completed_at');
  final firstMonth = varchar('first_month', length: 16).notNull();
  final lastMonth = varchar('last_month', length: 16).notNull();
  final userCount = integer('user_count').notNull();
  final syncMode = varchar(
    'sync_mode',
    length: 16,
  ).notNull().withDefault("'full'");
  final status = varchar('status', length: 16).notNull();
  final recordCount = integer('record_count').notNull().withDefault('0');
  final reportCount = integer('report_count').notNull().withDefault('0');
  final errorMessage = text('error_message');

  @override
  String get tableName => 'sync_runs';
}

class SyncWindowsTable extends Table {
  final sourceKey = varchar('source_key', length: 255).primaryKey();
  final userId = varchar('user_id', length: 191).notNull();
  final periodStart = bigint('period_start').notNull();
  final periodEndExclusive = bigint('period_end_exclusive').notNull();
  final syncedAt = bigint('synced_at').notNull();

  @override
  String get tableName => 'sync_windows';

  @override
  List<Index> defineIndexes() => [
    index('idx_sync_window_period').on([periodStart, periodEndExclusive]),
  ];
}

class MonthlyReportSnapshotsTable extends Table {
  final sourceKey = varchar('source_key', length: 512).primaryKey();
  final userId = varchar('user_id', length: 191).notNull();
  final year = integer('year').notNull();
  final periodStart = bigint('period_start').notNull();
  final periodEndExclusive = bigint('period_end_exclusive').notNull();
  final reportJson = text('report_json').notNull();
  final syncedAt = bigint('synced_at').notNull();

  @override
  String get tableName => 'monthly_report_snapshots';

  @override
  List<Index> defineIndexes() => [
    index('idx_report_year_user').on([year, userId]),
  ];
}

class AttendanceDateColumn extends DateTimeColumn {
  AttendanceDateColumn(super.name) : super(type: 'DATE');

  @override
  Object? encode(DateTime? value) {
    if (value == null) {
      return null;
    }
    return _dateKey(value);
  }

  @override
  DateTime? decode(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is DateTime) {
      return DateTime(raw.year, raw.month, raw.day);
    }
    final parsed = DateTime.tryParse(raw.toString());
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }
}

AttendanceDateColumn attendanceDateColumn(String name) {
  final column = AttendanceDateColumn(name);
  Column.track(column);
  return column;
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
