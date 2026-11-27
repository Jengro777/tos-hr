import 'package:flutter_test/flutter_test.dart';
import 'package:tospino_hr/data/checkin_record.dart';

void main() {
  test('parses a complete check-in response item', () {
    final record = CheckinRecord.fromJson({
      'userid': 'james',
      'groupname': '打卡一组',
      'checkin_type': '上班打卡',
      'exception_type': '地点异常',
      'checkin_time': 1492617610,
      'location_title': '依澜府',
      'location_detail': '四川省成都市武侯区益州大道中段784号附近',
      'wifiname': '办公一区',
      'notes': '路上堵车',
      'wifimac': '3c:46:d8:0c:7a:70',
      'mediaids': ['media-1'],
      'lat': 30547645,
      'lng': 104063236,
      'deviceid': 'device-1',
      'sch_checkin_time': 1492617600,
      'groupid': 1,
      'schedule_id': 3,
      'timeline_id': 2,
    });

    expect(record.userId, 'james');
    expect(record.groupName, '打卡一组');
    expect(record.hasException, isTrue);
    expect(record.latitude, closeTo(30.547645, 0.000001));
    expect(record.longitude, closeTo(104.063236, 0.000001));
    expect(record.mediaIds, ['media-1']);
    expect(record.deviceId, 'device-1');
    expect(record.groupId, 1);
    expect(
      record.checkinTime.toUtc(),
      DateTime.fromMillisecondsSinceEpoch(1492617610 * 1000, isUtc: true),
    );
  });

  test('requires a valid checkin_time', () {
    expect(
      () => CheckinRecord.fromJson({'userid': 'james'}),
      throwsFormatException,
    );
  });
}
