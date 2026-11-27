import '../config/database_config.dart';
import 'attendance_database.dart';
import 'attendance_database_factory_stub.dart'
    if (dart.library.io) 'attendance_database_factory_io.dart'
    as implementation;

AttendanceDatabase createAttendanceDatabase({DatabaseConfig? config}) =>
    implementation.createAttendanceDatabase(config);
