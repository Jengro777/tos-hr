class MonthlyReport {
  const MonthlyReport({
    required this.baseInfo,
    required this.summary,
    this.exceptions = const [],
    this.specialItems = const [],
    this.overwork,
  });

  factory MonthlyReport.fromJson(Map<String, dynamic> json) {
    final base = json['base_info'];
    final summary = json['summary_info'];
    if (base is! Map || summary is! Map) {
      throw const FormatException('月报缺少 base_info 或 summary_info');
    }
    return MonthlyReport(
      baseInfo: MonthlyBaseInfo.fromJson(Map<String, dynamic>.from(base)),
      summary: MonthlySummary.fromJson(Map<String, dynamic>.from(summary)),
      exceptions: _mapObjects(
        json['exception_infos'],
        MonthlyExceptionInfo.fromJson,
      ),
      specialItems: _mapObjects(json['sp_items'], MonthlySpecialItem.fromJson),
      overwork: json['overwork_info'] is Map
          ? MonthlyOverworkInfo.fromJson(
              Map<String, dynamic>.from(json['overwork_info'] as Map),
            )
          : null,
    );
  }

  final MonthlyBaseInfo baseInfo;
  final MonthlySummary summary;
  final List<MonthlyExceptionInfo> exceptions;
  final List<MonthlySpecialItem> specialItems;
  final MonthlyOverworkInfo? overwork;

  String get userId => baseInfo.accountId;
  String get displayName =>
      baseInfo.name.isNotEmpty ? baseInfo.name : baseInfo.accountId;

  Map<String, Object?> toJson() {
    return {
      'base_info': baseInfo.toJson(),
      'summary_info': summary.toJson(),
      'exception_infos': [for (final item in exceptions) item.toJson()],
      'sp_items': [for (final item in specialItems) item.toJson()],
      if (overwork != null) 'overwork_info': overwork!.toJson(),
    };
  }
}

class MonthlyBaseInfo {
  const MonthlyBaseInfo({
    this.recordType = 0,
    this.name = '',
    this.nameEx = '',
    this.departmentsName = '',
    this.groupId,
    this.groupName = '',
    this.accountId = '',
  });

  factory MonthlyBaseInfo.fromJson(Map<String, dynamic> json) {
    final ruleInfo = json['rule_info'] is Map
        ? Map<String, dynamic>.from(json['rule_info'] as Map)
        : const <String, dynamic>{};
    return MonthlyBaseInfo(
      recordType: _asInt(json['record_type']) ?? 0,
      name: _asString(json['name']),
      nameEx: _asString(json['name_ex']),
      departmentsName: _asString(json['departs_name']),
      groupId: _asInt(ruleInfo['groupid']),
      groupName: _asString(ruleInfo['groupname']),
      accountId: _asString(json['acctid']),
    );
  }

  final int recordType;
  final String name;
  final String nameEx;
  final String departmentsName;
  final int? groupId;
  final String groupName;
  final String accountId;

  Map<String, Object?> toJson() {
    return {
      'record_type': recordType,
      'name': name,
      'name_ex': nameEx,
      'departs_name': departmentsName,
      'rule_info': {'groupid': groupId, 'groupname': groupName},
      'acctid': accountId,
    };
  }
}

class MonthlySummary {
  const MonthlySummary({
    this.workDays = 0,
    this.regularDays = 0,
    this.restDays = 0,
    this.exceptionDays = 0,
    this.regularWorkSeconds = 0,
    this.standardWorkSeconds = 0,
  });

  factory MonthlySummary.fromJson(Map<String, dynamic> json) {
    return MonthlySummary(
      workDays: _asInt(json['work_days']) ?? 0,
      regularDays: _asInt(json['regular_days']) ?? 0,
      restDays: _asInt(json['rest_days']) ?? 0,
      exceptionDays: _asInt(json['except_days']) ?? 0,
      regularWorkSeconds: _asInt(json['regular_work_sec']) ?? 0,
      standardWorkSeconds: _asInt(json['standard_work_sec']) ?? 0,
    );
  }

  final int workDays;
  final int regularDays;
  final int restDays;
  final int exceptionDays;
  final int regularWorkSeconds;
  final int standardWorkSeconds;

  String get regularWorkText => formatWorkDuration(regularWorkSeconds);
  String get standardWorkText => formatWorkDuration(standardWorkSeconds);

  Map<String, Object?> toJson() {
    return {
      'work_days': workDays,
      'regular_days': regularDays,
      'rest_days': restDays,
      'except_days': exceptionDays,
      'regular_work_sec': regularWorkSeconds,
      'standard_work_sec': standardWorkSeconds,
    };
  }
}

class MonthlyExceptionInfo {
  const MonthlyExceptionInfo({
    required this.type,
    this.count = 0,
    this.durationSeconds = 0,
  });

  factory MonthlyExceptionInfo.fromJson(Map<String, dynamic> json) {
    return MonthlyExceptionInfo(
      type: _asInt(json['exception']) ?? 0,
      count: _asInt(json['count']) ?? 0,
      durationSeconds: _asInt(json['duration']) ?? 0,
    );
  }

  final int type;
  final int count;
  final int durationSeconds;

  String get label => switch (type) {
    1 => '迟到',
    2 => '早退',
    3 => '缺卡',
    4 => '旷工',
    5 => '地点异常',
    6 => '设备异常',
    _ => '异常 $type',
  };

  Map<String, Object?> toJson() {
    return {'exception': type, 'count': count, 'duration': durationSeconds};
  }
}

class MonthlySpecialItem {
  const MonthlySpecialItem({
    required this.type,
    this.vacationId = 0,
    this.count = 0,
    this.duration = 0,
    this.timeType = 0,
    this.name = '',
  });

  factory MonthlySpecialItem.fromJson(Map<String, dynamic> json) {
    return MonthlySpecialItem(
      type: _asInt(json['type']) ?? 0,
      vacationId: _asInt(json['vacation_id']) ?? 0,
      count: _asInt(json['count']) ?? 0,
      duration: _asInt(json['duration']) ?? 0,
      timeType: _asInt(json['time_type']) ?? 0,
      name: _asString(json['name']),
    );
  }

  final int type;
  final int vacationId;
  final int count;
  final int duration;
  final int timeType;
  final String name;

  String get label {
    if (name.isNotEmpty) {
      return name;
    }
    return switch (type) {
      1 => '请假',
      2 => '补卡',
      3 => '出差',
      4 => '外出',
      15 => '审批打卡',
      100 => '外勤',
      _ => '假勤 $type',
    };
  }

  String get durationText {
    if (duration == 0) {
      return '';
    }
    if (timeType == 1) {
      return _formatDecimal(duration / 3600, '小时');
    }
    return _formatDecimal(duration / 86400, '天');
  }

  Map<String, Object?> toJson() {
    return {
      'type': type,
      'vacation_id': vacationId,
      'count': count,
      'duration': duration,
      'time_type': timeType,
      'name': name,
    };
  }
}

class MonthlyOverworkInfo {
  const MonthlyOverworkInfo({
    this.workdaySeconds = 0,
    this.restDaySeconds = 0,
    this.holidaySeconds = 0,
    this.workdayAsVacationSeconds = 0,
    this.workdayAsMoneySeconds = 0,
    this.restDayAsVacationSeconds = 0,
    this.restDayAsMoneySeconds = 0,
    this.holidayAsVacationSeconds = 0,
    this.holidayAsMoneySeconds = 0,
  });

  factory MonthlyOverworkInfo.fromJson(Map<String, dynamic> json) {
    return MonthlyOverworkInfo(
      workdaySeconds: _asInt(json['workday_over_sec']) ?? 0,
      restDaySeconds: _asInt(json['restdays_over_sec']) ?? 0,
      holidaySeconds: _asInt(json['holidays_over_sec']) ?? 0,
      workdayAsVacationSeconds: _asInt(json['workdays_over_as_vacation']) ?? 0,
      workdayAsMoneySeconds: _asInt(json['workdays_over_as_money']) ?? 0,
      restDayAsVacationSeconds: _asInt(json['restdays_over_as_vacation']) ?? 0,
      restDayAsMoneySeconds: _asInt(json['restdays_over_as_money']) ?? 0,
      holidayAsVacationSeconds: _asInt(json['holidays_over_as_vacation']) ?? 0,
      holidayAsMoneySeconds: _asInt(json['holidays_over_as_money']) ?? 0,
    );
  }

  final int workdaySeconds;
  final int restDaySeconds;
  final int holidaySeconds;
  final int workdayAsVacationSeconds;
  final int workdayAsMoneySeconds;
  final int restDayAsVacationSeconds;
  final int restDayAsMoneySeconds;
  final int holidayAsVacationSeconds;
  final int holidayAsMoneySeconds;

  int get totalSeconds => workdaySeconds + restDaySeconds + holidaySeconds;
  String get totalText => formatWorkDuration(totalSeconds);

  Map<String, Object?> toJson() {
    return {
      'workday_over_sec': workdaySeconds,
      'restdays_over_sec': restDaySeconds,
      'holidays_over_sec': holidaySeconds,
      'workdays_over_as_vacation': workdayAsVacationSeconds,
      'workdays_over_as_money': workdayAsMoneySeconds,
      'restdays_over_as_vacation': restDayAsVacationSeconds,
      'restdays_over_as_money': restDayAsMoneySeconds,
      'holidays_over_as_vacation': holidayAsVacationSeconds,
      'holidays_over_as_money': holidayAsMoneySeconds,
    };
  }
}

String formatWorkDuration(int seconds) {
  if (seconds <= 0) {
    return '0 分钟';
  }
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours == 0) {
    return '$minutes 分钟';
  }
  if (minutes == 0) {
    return '$hours 小时';
  }
  return '$hours 小时 $minutes 分钟';
}

List<T> _mapObjects<T>(Object? value, T Function(Map<String, dynamic>) parser) {
  if (value is! List) {
    return const [];
  }
  return value
      .whereType<Map>()
      .map((item) => parser(Map<String, dynamic>.from(item)))
      .toList(growable: false);
}

String _asString(Object? value) => value?.toString().trim() ?? '';

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

String _formatDecimal(double value, String unit) {
  final fixed = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  return '$fixed$unit';
}
