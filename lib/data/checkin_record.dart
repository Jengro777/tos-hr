import 'package:intl/intl.dart';

enum CheckinDataType {
  clockIn(1, '上下班打卡'),
  outside(2, '外出打卡'),
  all(3, '全部打卡');

  const CheckinDataType(this.apiValue, this.label);

  final int apiValue;
  final String label;
}

class CheckinRecord {
  const CheckinRecord({
    required this.userId,
    this.groupName = '',
    this.checkinType = '',
    this.exceptionType = '',
    required this.checkinTime,
    this.locationTitle = '',
    this.locationDetail = '',
    this.wifiName = '',
    this.notes = '',
    this.wifiMac = '',
    this.mediaIds = const [],
    this.latitude,
    this.longitude,
    this.deviceId = '',
    this.scheduleCheckinTime,
    this.groupId,
    this.scheduleId,
    this.timelineId,
  });

  factory CheckinRecord.fromJson(Map<String, dynamic> json) {
    final checkinSeconds = _asInt(json['checkin_time']);
    if (checkinSeconds == null) {
      throw const FormatException('打卡记录缺少有效的 checkin_time');
    }

    final scheduleSeconds = _asInt(json['sch_checkin_time']);
    return CheckinRecord(
      userId: _asString(json['userid']),
      groupName: _asString(json['groupname']),
      checkinType: _asString(json['checkin_type']),
      exceptionType: _asString(json['exception_type']),
      checkinTime: DateTime.fromMillisecondsSinceEpoch(
        checkinSeconds * 1000,
        isUtc: true,
      ).toLocal(),
      locationTitle: _asString(json['location_title']),
      locationDetail: _asString(json['location_detail']),
      wifiName: _asString(json['wifiname']),
      notes: _asString(json['notes']),
      wifiMac: _asString(json['wifimac']),
      mediaIds: _asStringList(json['mediaids']),
      latitude: _asCoordinate(json['lat']),
      longitude: _asCoordinate(json['lng']),
      deviceId: _asString(json['deviceid']),
      scheduleCheckinTime: scheduleSeconds == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              scheduleSeconds * 1000,
              isUtc: true,
            ).toLocal(),
      groupId: _asInt(json['groupid']),
      scheduleId: _asInt(json['schedule_id']),
      timelineId: _asInt(json['timeline_id']),
    );
  }

  final String userId;
  final String groupName;
  final String checkinType;
  final String exceptionType;
  final DateTime checkinTime;
  final String locationTitle;
  final String locationDetail;
  final String wifiName;
  final String notes;
  final String wifiMac;
  final List<String> mediaIds;
  final double? latitude;
  final double? longitude;
  final String deviceId;
  final DateTime? scheduleCheckinTime;
  final int? groupId;
  final int? scheduleId;
  final int? timelineId;

  bool get hasException => exceptionType.trim().isNotEmpty;

  String get sourceKey {
    final sourceParts = [
      userId,
      checkinTime.millisecondsSinceEpoch.toString(),
      checkinType,
      groupId?.toString() ?? '',
      scheduleId?.toString() ?? '',
      timelineId?.toString() ?? '',
      locationTitle,
      deviceId,
    ];
    return sourceParts.join('|');
  }

  String get localRecordDate => DateFormat('yyyy-MM-dd').format(checkinTime);

  String get formattedCheckinTime =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(checkinTime);

  String get formattedScheduleTime => scheduleCheckinTime == null
      ? ''
      : DateFormat('HH:mm').format(scheduleCheckinTime!);

  String? get coordinates {
    if (latitude == null || longitude == null) {
      return null;
    }
    return '${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}';
  }
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

double? _asCoordinate(Object? value) {
  final raw = value is num ? value.toDouble() : double.tryParse('$value');
  if (raw == null) {
    return null;
  }
  // 企微经纬度是实际坐标的 1,000,000 倍。
  return raw.abs() > 1000 ? raw / 1000000 : raw;
}

List<String> _asStringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.map((item) => item.toString()).toList(growable: false);
}
