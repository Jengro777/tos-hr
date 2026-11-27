import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tospino_hr/data/attendance_summary.dart';
import 'package:tospino_hr/widgets/attendance_summary_table.dart';

void main() {
  testWidgets('renders the annual attendance table on a wide workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(find.text('分年汇总测试'), findsOneWidget);
    expect(find.text('吴振国'), findsOneWidget);
    expect(find.text('应出勤天数(天)'), findsOneWidget);
    expect(find.text('合计'), findsOneWidget);
    await tester.tap(find.text('吴振国'));
    await tester.pumpAndSettle();
    expect(find.text('地点异常(次)'), findsWidgets);
    expect(find.text('设备异常(次)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps annual summary filters usable on a phone-width layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(find.text('吴振国'), findsOneWidget);
    expect(
      find.text(
        '应出勤、正常天数、异常和实际工时取自企业微信月报；实际出勤天数'
        '取自真实上下班打卡日期，并排除“未打卡”排班占位记录。'
        '点击姓名可查看全部 SQL 统计明细。',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _testApp() {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('分年汇总测试'),
            const SizedBox(height: 12),
            AttendanceSummaryTable(
              rows: [
                _row(year: 2025, name: '吴振国', userId: 'PM07', exceptions: 2),
                _row(year: 2026, name: '蒙林昌', userId: 'test03'),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

AttendanceSummaryRow _row({
  required int year,
  required String name,
  required String userId,
  int exceptions = 0,
}) {
  return AttendanceSummaryRow(
    year: year,
    name: name,
    userId: userId,
    ruleNames: '平台打卡',
    departments: 'Tospino/平台',
    sourceRecordCount: 6,
    metrics: {
      for (final metric in AttendanceMetric.values) metric: 0,
      AttendanceMetric.expectedDays: 240,
      AttendanceMetric.exceptionDays: exceptions.toDouble(),
      AttendanceMetric.regularWorkHours: 1920,
    },
  );
}
