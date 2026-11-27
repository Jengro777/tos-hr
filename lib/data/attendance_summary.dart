import 'monthly_report.dart';

enum AttendanceMetric {
  checkinRecordCount('打卡记录(条)', 0),
  attendanceDays('实际出勤天数(天)', 0),
  normalAttendanceDays('无异常出勤天数(天)', 0),
  expectedDays('应出勤天数(天)', 0),
  restDays('休息天数(天)', 0),
  regularDays('正常天数(天)', 0),
  exceptionDays('异常天数(天)', 0),
  standardWorkHours('标准工作时长(小时)', 1),
  regularWorkHours('实际工作时长(小时)', 1),
  exceptionCount('异常合计(次)', 0),
  timeExceptionCount('时间异常(次)', 0),
  notCheckedInCount('未打卡(次)', 0),
  wifiExceptionCount('WiFi异常(次)', 0),
  lateCount('迟到次数(次)', 0),
  lateMinutes('迟到时长(分钟)', 0),
  earlyLeaveCount('早退次数(次)', 0),
  earlyLeaveMinutes('早退时长(分钟)', 0),
  absenceCount('旷工次数(次)', 0),
  absenceMinutes('旷工时长(分钟)', 0),
  missingCardCount('缺卡次数(次)', 0),
  locationExceptionCount('地点异常(次)', 0),
  deviceExceptionCount('设备异常(次)', 0),
  correctionCount('补卡次数(次)', 0),
  approvalCheckinCount('审批打卡次数(次)', 0),
  fieldCount('外勤次数(次)', 0),
  outsideHours('外出(小时)', 1),
  businessTripDays('出差(天)', 1),
  annualLeaveHours('年假(小时)', 1),
  personalLeaveHours('事假(小时)', 1),
  sickLeaveHours('病假(小时)', 1),
  compensatoryLeaveHours('调休假(小时)', 1),
  marriageLeaveHours('婚假(小时)', 1),
  maternityLeaveDays('产假(天)', 1),
  paternityLeaveDays('陪产假(天)', 1),
  otherHours('其他(小时)', 1),
  overtimeHours('加班时长(小时)', 1),
  workdayOvertimeHours('工作日加班时长(小时)', 1),
  workdayOvertimeAsLeaveHours('工作日加班计为调休(小时)', 1),
  workdayOvertimeAsPayHours('工作日加班计为加班费(小时)', 1),
  restdayOvertimeHours('休息日加班时长(小时)', 1),
  restdayOvertimeAsLeaveHours('休息日加班计为调休(小时)', 1),
  restdayOvertimeAsPayHours('休息日加班计为加班费(小时)', 1),
  holidayOvertimeHours('节假日加班时长(小时)', 1),
  holidayOvertimeAsLeaveHours('节假日加班计为调休(小时)', 1),
  holidayOvertimeAsPayHours('节假日加班计为加班费(小时)', 1);

  const AttendanceMetric(this.label, this.decimalPlaces);

  final String label;
  final int decimalPlaces;
}

class AttendanceSummaryRow {
  const AttendanceSummaryRow({
    required this.year,
    this.month,
    this.periodLabelOverride,
    required this.name,
    required this.userId,
    required this.ruleNames,
    required this.departments,
    required this.sourceRecordCount,
    required this.metrics,
  });

  final int year;
  final int? month;
  final String? periodLabelOverride;
  final String name;
  final String userId;
  final String ruleNames;
  final String departments;
  final int sourceRecordCount;
  final Map<AttendanceMetric, double> metrics;

  double valueOf(AttendanceMetric metric) => metrics[metric] ?? 0;

  String get periodLabel =>
      periodLabelOverride ??
      (month == null
          ? '$year'
          : '${year.toString().padLeft(4, '0')}-'
                '${month.toString().padLeft(2, '0')}');

  bool get hasException => valueOf(AttendanceMetric.exceptionDays) > 0;

  String get searchableText =>
      '$name $userId $ruleNames $departments'.toLowerCase();

  AttendanceSummaryRow withMetric(AttendanceMetric metric, double value) {
    return AttendanceSummaryRow(
      year: year,
      month: month,
      periodLabelOverride: periodLabelOverride,
      name: name,
      userId: userId,
      ruleNames: ruleNames,
      departments: departments,
      sourceRecordCount: sourceRecordCount,
      metrics: Map<AttendanceMetric, double>.unmodifiable({
        ...metrics,
        metric: value,
      }),
    );
  }
}

class AttendanceSyncWindow {
  const AttendanceSyncWindow({
    required this.year,
    required this.start,
    required this.endExclusive,
  });

  final int year;
  final DateTime start;
  final DateTime endExclusive;

  DateTime get endInclusive =>
      endExclusive.subtract(const Duration(milliseconds: 1));

  String get label {
    final lastDay = endInclusive;
    return '${start.year}-${_twoDigits(start.month)}-${_twoDigits(start.day)} 至 '
        '${lastDay.year}-${_twoDigits(lastDay.month)}-'
        '${_twoDigits(lastDay.day)}';
  }
}

List<AttendanceSyncWindow> buildAttendanceSyncWindows(
  DateTime firstMonth,
  DateTime lastMonth, {
  DateTime? startAt,
}) {
  final selectedStart = startAt == null
      ? DateTime(firstMonth.year, firstMonth.month)
      : DateTime(startAt.year, startAt.month, startAt.day);
  final selectedEnd = DateTime(lastMonth.year, lastMonth.month + 1);
  final windows = <AttendanceSyncWindow>[];

  for (var year = selectedStart.year; year <= lastMonth.year; year++) {
    for (var month = 1; month <= 12; month++) {
      final monthStart = DateTime(year, month);
      if (!monthStart.isBefore(selectedEnd)) {
        break;
      }
      final monthEnd = DateTime(year, month + 1);
      final candidates = [
        (monthStart, DateTime(year, month, 16)),
        (DateTime(year, month, 16), monthEnd),
      ];
      for (final (rawStart, rawEnd) in candidates) {
        final clippedStart = rawStart.isBefore(selectedStart)
            ? selectedStart
            : rawStart;
        final clippedEnd = rawEnd.isAfter(selectedEnd) ? selectedEnd : rawEnd;
        if (clippedStart.isBefore(clippedEnd)) {
          windows.add(
            AttendanceSyncWindow(
              year: year,
              start: clippedStart,
              endExclusive: clippedEnd,
            ),
          );
        }
      }
    }
  }
  return windows;
}

List<AttendanceSyncWindow> buildAttendanceReportSyncWindows(
  DateTime firstMonth,
  DateTime lastMonth, {
  DateTime? startAt,
}) {
  final selectedStart = startAt == null
      ? DateTime(firstMonth.year, firstMonth.month)
      : DateTime(startAt.year, startAt.month);
  final selectedEnd = DateTime(lastMonth.year, lastMonth.month + 1);
  final windows = <AttendanceSyncWindow>[];

  for (var year = selectedStart.year; year <= lastMonth.year; year++) {
    for (var month = 1; month <= 12; month++) {
      final monthStart = DateTime(year, month);
      if (!monthStart.isBefore(selectedEnd)) {
        break;
      }
      final monthEnd = DateTime(year, month + 1);
      final clippedStart = monthStart.isBefore(selectedStart)
          ? selectedStart
          : monthStart;
      final clippedEnd = monthEnd.isAfter(selectedEnd) ? selectedEnd : monthEnd;
      if (clippedStart.isBefore(clippedEnd)) {
        windows.add(
          AttendanceSyncWindow(
            year: year,
            start: clippedStart,
            endExclusive: clippedEnd,
          ),
        );
      }
    }
  }
  return windows;
}

DateTime attendanceHalfMonthStart(DateTime value) {
  return DateTime(value.year, value.month, value.day >= 16 ? 16 : 1);
}

DateTime? resolveAttendanceIncrementalStart({
  required DateTime? latestCheckinAt,
  required DateTime? latestReportAt,
}) {
  if (latestCheckinAt == null || latestReportAt == null) {
    return null;
  }
  final checkinStart = attendanceHalfMonthStart(latestCheckinAt);
  final reportStart = attendanceHalfMonthStart(latestReportAt);
  return checkinStart.isBefore(reportStart) ? checkinStart : reportStart;
}

class AttendanceSummaryBuilder {
  final Map<String, _AttendanceAccumulator> _rows = {};

  void addReports(Iterable<MonthlyReport> reports, {required int year}) {
    for (final report in reports) {
      final userId = report.userId.trim();
      final name = report.displayName.trim();
      final key = '$year\u0000${userId.isNotEmpty ? userId : name}';
      final accumulator = _rows.putIfAbsent(
        key,
        () => _AttendanceAccumulator(year: year, name: name, userId: userId),
      );
      accumulator.add(report);
    }
  }

  List<AttendanceSummaryRow> build() {
    return _rows.values
        .where((row) => row.hasAttendanceData)
        .map((row) => row.build())
        .toList(growable: false)
      ..sort((a, b) {
        final yearComparison = a.year.compareTo(b.year);
        if (yearComparison != 0) {
          return yearComparison;
        }
        final nameComparison = a.name.compareTo(b.name);
        if (nameComparison != 0) {
          return nameComparison;
        }
        return a.userId.compareTo(b.userId);
      });
  }
}

class AttendanceMonthlySummaryBuilder {
  final Map<String, _AttendanceAccumulator> _rows = {};

  void addReports(
    Iterable<MonthlyReport> reports, {
    required int year,
    required int month,
  }) {
    for (final report in reports) {
      final userId = report.userId.trim();
      final name = report.displayName.trim();
      final key = '$year-$month\u0000${userId.isNotEmpty ? userId : name}';
      final accumulator = _rows.putIfAbsent(
        key,
        () => _AttendanceAccumulator(
          year: year,
          month: month,
          name: name,
          userId: userId,
        ),
      );
      accumulator.add(report);
    }
  }

  List<AttendanceSummaryRow> build() {
    return _rows.values
        .where((row) => row.hasAttendanceData)
        .map((row) => row.build())
        .toList(growable: false)
      ..sort((a, b) {
        final periodComparison = b.periodLabel.compareTo(a.periodLabel);
        if (periodComparison != 0) {
          return periodComparison;
        }
        final nameComparison = a.name.compareTo(b.name);
        if (nameComparison != 0) {
          return nameComparison;
        }
        return a.userId.compareTo(b.userId);
      });
  }
}

List<AttendanceSummaryRow> aggregateAttendanceAllTime(
  Iterable<AttendanceSummaryRow> rows,
) {
  final grouped = <String, _EmployeeAllTimeAccumulator>{};
  for (final row in rows) {
    final key = row.userId.isNotEmpty ? row.userId : row.name;
    final accumulator = grouped.putIfAbsent(
      key,
      () => _EmployeeAllTimeAccumulator(name: row.name, userId: row.userId),
    );
    accumulator.add(row);
  }
  return grouped.values.map((row) => row.build()).toList(growable: false)
    ..sort((a, b) {
      final nameComparison = a.name.compareTo(b.name);
      if (nameComparison != 0) {
        return nameComparison;
      }
      return a.userId.compareTo(b.userId);
    });
}

class _AttendanceAccumulator {
  _AttendanceAccumulator({
    required this.year,
    this.month,
    required this.name,
    required this.userId,
  });

  final int year;
  final int? month;
  final String name;
  final String userId;
  final Set<String> _ruleNames = {};
  final Set<String> _departments = {};
  final Map<AttendanceMetric, double> _metrics = {
    for (final metric in AttendanceMetric.values) metric: 0,
  };
  int _sourceRecordCount = 0;

  bool get hasAttendanceData => _metrics.entries.any(
    (entry) =>
        entry.key != AttendanceMetric.checkinRecordCount && entry.value > 0,
  );

  void add(MonthlyReport report) {
    _sourceRecordCount++;
    _addText(_ruleNames, report.baseInfo.groupName);
    _addText(_departments, report.baseInfo.departmentsName);

    final summary = report.summary;
    _add(AttendanceMetric.expectedDays, summary.workDays);
    _add(AttendanceMetric.restDays, summary.restDays);
    _add(AttendanceMetric.regularDays, summary.regularDays);
    _add(AttendanceMetric.normalAttendanceDays, summary.regularDays);
    _add(AttendanceMetric.exceptionDays, summary.exceptionDays);
    _add(
      AttendanceMetric.standardWorkHours,
      summary.standardWorkSeconds / 3600,
    );
    _add(AttendanceMetric.regularWorkHours, summary.regularWorkSeconds / 3600);

    for (final item in report.exceptions) {
      _add(AttendanceMetric.exceptionCount, item.count);
      switch (item.type) {
        case 1:
          _add(AttendanceMetric.lateCount, item.count);
          _add(AttendanceMetric.lateMinutes, item.durationSeconds / 60);
          break;
        case 2:
          _add(AttendanceMetric.earlyLeaveCount, item.count);
          _add(AttendanceMetric.earlyLeaveMinutes, item.durationSeconds / 60);
          break;
        case 3:
          _add(AttendanceMetric.missingCardCount, item.count);
          break;
        case 4:
          _add(AttendanceMetric.absenceCount, item.count);
          _add(AttendanceMetric.absenceMinutes, item.durationSeconds / 60);
          break;
        case 5:
          _add(AttendanceMetric.locationExceptionCount, item.count);
          break;
        case 6:
          _add(AttendanceMetric.deviceExceptionCount, item.count);
          break;
      }
    }

    for (final item in report.specialItems) {
      switch (item.type) {
        case 1:
          _addLeave(item);
          break;
        case 2:
          _add(AttendanceMetric.correctionCount, item.count);
          break;
        case 3:
          if (item.timeType == 0) {
            _add(AttendanceMetric.businessTripDays, item.duration / 86400);
          }
          break;
        case 4:
          if (item.timeType == 1) {
            _add(AttendanceMetric.outsideHours, item.duration / 3600);
          }
          break;
        case 15:
          _add(AttendanceMetric.approvalCheckinCount, item.count);
          break;
        case 100:
          _add(AttendanceMetric.fieldCount, item.count);
          break;
      }
    }

    final overwork = report.overwork;
    if (overwork != null) {
      final totalSeconds =
          overwork.workdaySeconds +
          overwork.restDaySeconds +
          overwork.holidaySeconds;
      _add(AttendanceMetric.overtimeHours, totalSeconds / 3600);
      _add(
        AttendanceMetric.workdayOvertimeHours,
        overwork.workdaySeconds / 3600,
      );
      _add(
        AttendanceMetric.workdayOvertimeAsLeaveHours,
        overwork.workdayAsVacationSeconds / 3600,
      );
      _add(
        AttendanceMetric.workdayOvertimeAsPayHours,
        overwork.workdayAsMoneySeconds / 3600,
      );
      _add(
        AttendanceMetric.restdayOvertimeHours,
        overwork.restDaySeconds / 3600,
      );
      _add(
        AttendanceMetric.restdayOvertimeAsLeaveHours,
        overwork.restDayAsVacationSeconds / 3600,
      );
      _add(
        AttendanceMetric.restdayOvertimeAsPayHours,
        overwork.restDayAsMoneySeconds / 3600,
      );
      _add(
        AttendanceMetric.holidayOvertimeHours,
        overwork.holidaySeconds / 3600,
      );
      _add(
        AttendanceMetric.holidayOvertimeAsLeaveHours,
        overwork.holidayAsVacationSeconds / 3600,
      );
      _add(
        AttendanceMetric.holidayOvertimeAsPayHours,
        overwork.holidayAsMoneySeconds / 3600,
      );
    }
  }

  void _addLeave(MonthlySpecialItem item) {
    final hours = item.timeType == 1 ? item.duration / 3600 : null;
    final days = item.timeType == 0 ? item.duration / 86400 : null;
    switch (item.name.trim()) {
      case '年假':
        if (hours != null) {
          _add(AttendanceMetric.annualLeaveHours, hours);
        }
        break;
      case '事假':
        if (hours != null) {
          _add(AttendanceMetric.personalLeaveHours, hours);
        }
        break;
      case '病假':
        if (hours != null) {
          _add(AttendanceMetric.sickLeaveHours, hours);
        }
        break;
      case '调休假':
        if (hours != null) {
          _add(AttendanceMetric.compensatoryLeaveHours, hours);
        }
        break;
      case '婚假':
        if (hours != null) {
          _add(AttendanceMetric.marriageLeaveHours, hours);
        }
        break;
      case '产假':
        if (days != null) {
          _add(AttendanceMetric.maternityLeaveDays, days);
        }
        break;
      case '陪产假':
        if (days != null) {
          _add(AttendanceMetric.paternityLeaveDays, days);
        }
        break;
      default:
        if (hours != null) {
          _add(AttendanceMetric.otherHours, hours);
        }
        break;
    }
  }

  void _add(AttendanceMetric metric, num value) {
    _metrics[metric] = (_metrics[metric] ?? 0) + value.toDouble();
  }

  void _addText(Set<String> target, String value) {
    for (final part in value.split(RegExp(r'[;；]'))) {
      final normalized = part.trim();
      if (normalized.isNotEmpty) {
        target.add(normalized);
      }
    }
  }

  AttendanceSummaryRow build() {
    return AttendanceSummaryRow(
      year: year,
      month: month,
      name: name.isEmpty ? userId : name,
      userId: userId,
      ruleNames: _ruleNames.isEmpty ? '--' : _ruleNames.join('；'),
      departments: _departments.isEmpty ? '--' : _departments.join('；'),
      sourceRecordCount: _sourceRecordCount,
      metrics: Map<AttendanceMetric, double>.unmodifiable(_metrics),
    );
  }
}

class _EmployeeAllTimeAccumulator {
  _EmployeeAllTimeAccumulator({required this.name, required this.userId});

  final String name;
  final String userId;
  final Set<String> _ruleNames = {};
  final Set<String> _departments = {};
  final Map<AttendanceMetric, double> _metrics = {
    for (final metric in AttendanceMetric.values) metric: 0,
  };
  int _sourceRecordCount = 0;

  void add(AttendanceSummaryRow row) {
    _sourceRecordCount += row.sourceRecordCount;
    _ruleNames.addAll(_splitText(row.ruleNames));
    _departments.addAll(_splitText(row.departments));
    for (final metric in AttendanceMetric.values) {
      _metrics[metric] = (_metrics[metric] ?? 0) + row.valueOf(metric);
    }
  }

  AttendanceSummaryRow build() {
    return AttendanceSummaryRow(
      year: 0,
      periodLabelOverride: '全部历史',
      name: name,
      userId: userId,
      ruleNames: _ruleNames.isEmpty ? '--' : _ruleNames.join('；'),
      departments: _departments.isEmpty ? '--' : _departments.join('；'),
      sourceRecordCount: _sourceRecordCount,
      metrics: Map<AttendanceMetric, double>.unmodifiable(_metrics),
    );
  }
}

Set<String> _splitText(String value) {
  return value
      .split(RegExp(r'[;；]'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty && part != '--')
      .toSet();
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
