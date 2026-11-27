import '../config/database_config.dart';
import 'attendance_database.dart';
import 'tidb_attendance_database.dart';

AttendanceDatabase createAttendanceDatabase(DatabaseConfig? config) {
  return TiDbAttendanceDatabase(
    config: config ?? DatabaseConfig.fromEnvironment(),
  );
}
