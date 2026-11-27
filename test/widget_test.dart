import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tospino_hr/config/wecom_config.dart';
import 'package:tospino_hr/data/attendance_database.dart';
import 'package:tospino_hr/data/attendance_summary.dart';
import 'package:tospino_hr/data/connection_status.dart';
import 'package:tospino_hr/main.dart';

void main() {
  testWidgets('shows the check-in workspace when config is missing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const WecomCheckinApp(
        config: WecomConfig(corpId: '', agentId: '', secret: ''),
        initialAuthenticated: true,
      ),
    );

    expect(find.text('Tospino-HR'), findsOneWidget);
    expect(find.text('企业微信配置尚未完成'), findsOneWidget);
    expect(find.text('查询本地记录'), findsOneWidget);
  });

  testWidgets('shows all three report modes on a phone-width layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = _FakeAttendanceDatabase();

    await tester.pumpWidget(
      WecomCheckinApp(
        config: WecomConfig(
          corpId: 'ww-test-corp',
          agentId: '1000012',
          secret: 'test-secret',
        ),
        database: database,
        initialAuthenticated: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('打卡明细'), findsOneWidget);
    expect(find.text('月度汇总'), findsOneWidget);
    expect(find.text('分年汇总'), findsOneWidget);
    expect(find.text('历史汇总'), findsOneWidget);
    await tester.tap(find.text('月度汇总'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<int>), findsNWidgets(2));
    expect(find.text('成员 UserID'), findsNothing);
    await tester.tap(find.text('分年汇总'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    expect(find.text('成员 UserID'), findsNothing);
    expect(find.text('查看本地汇总'), findsOneWidget);
    expect(find.text('成员筛选'), findsOneWidget);
    expect(find.textContaining('动态获取'), findsNothing);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('连接状态'), findsOneWidget);
    expect(find.text('TiDB'), findsOneWidget);
    expect(find.text('企业微信'), findsOneWidget);
    expect(find.textContaining('测试连接'), findsNWidgets(2));
    expect(find.text('同步 API'), findsOneWidget);
    expect(find.text('数据库地址'), findsOneWidget);
    expect(find.text('AgentId'), findsOneWidget);
    expect(find.text('打卡 Secret'), findsOneWidget);
    expect(find.text('全量获取覆盖打卡记录'), findsOneWidget);
    expect(find.text('增量获取打卡记录'), findsOneWidget);
    await tester.ensureVisible(find.text('全量获取覆盖打卡记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全量获取覆盖打卡记录'));
    await tester.pumpAndSettle();
    expect(find.text('我已知晓全量获取时间较长，期间不可离开页面'), findsOneWidget);
    final confirmFinder = find.widgetWithText(FilledButton, '开始全量获取');
    expect(tester.widget<FilledButton>(confirmFinder).onPressed, isNull);
    await tester.enterText(
      find.byType(TextField).last,
      '我已知晓全量获取时间较长，期间不可离开页面',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(confirmFinder).onPressed, isNotNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('分年汇总'), const Offset(-160, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('历史汇总'));
    await tester.pumpAndSettle();
    expect(find.text('开始'), findsOneWidget);
    expect(find.text('结束'), findsOneWidget);
    expect(find.text('全部日期'), findsOneWidget);
    expect(find.text('成员 UserID'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a prompt when the database is unavailable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      WecomCheckinApp(
        config: const WecomConfig(
          corpId: 'ww-test-corp',
          agentId: '1000012',
          secret: 'test-secret',
        ),
        database: _UnavailableAttendanceDatabase(),
        initialAuthenticated: true,
      ),
    );
    await tester.tap(find.text('查询本地记录'));
    await tester.pumpAndSettle();

    expect(find.textContaining('数据库不可用'), findsWidgets);
  });
}

class _FakeAttendanceDatabase extends AttendanceDatabase {
  @override
  Future<ConnectionStatus> checkConnection() async {
    return ConnectionStatus(
      connected: true,
      message: '连接正常',
      checkedAt: DateTime.now(),
    );
  }

  @override
  Future<AttendanceDatabaseStats> loadStats() async {
    return const AttendanceDatabaseStats(
      checkinRecordCount: 0,
      monthlyReportCount: 0,
    );
  }

  @override
  Future<List<AttendanceSummaryRow>> loadSummary({
    required int firstYear,
    required int lastYear,
    Set<String> userIds = const {},
  }) async {
    return const [];
  }

  @override
  Future<void> close() async {}
}

class _UnavailableAttendanceDatabase extends _FakeAttendanceDatabase {
  @override
  Future<ConnectionStatus> checkConnection() async {
    return ConnectionStatus(
      connected: false,
      message: '数据库不可用',
      checkedAt: DateTime.now(),
    );
  }
}
