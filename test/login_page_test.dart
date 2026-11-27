import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tospino_hr/config/app_version.dart';
import 'package:tospino_hr/config/wecom_config.dart';
import 'package:tospino_hr/main.dart';

void main() {
  testWidgets('requires login before showing attendance workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const WecomCheckinApp(
        config: WecomConfig(corpId: '', agentId: '', secret: ''),
        versionInfo: AppVersionInfo(version: '0.1.14'),
      ),
    );

    expect(find.text('欢迎回来'), findsOneWidget);
    expect(find.text('版本 0.1.14'), findsOneWidget);
    expect(find.text('Debug 跳过登录'), findsOneWidget);
    expect(find.text('企业微信配置尚未完成'), findsNothing);

    await tester.enterText(find.byType(TextFormField).first, 'tospino');
    await tester.enterText(
      find.byType(TextFormField).last,
      ['Tospino', '88', '@'].join(),
    );
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.text('Tospino-HR'), findsOneWidget);
    expect(find.text('版本 0.1.14'), findsOneWidget);
    expect(find.text('企业微信配置尚未完成'), findsOneWidget);
  });

  testWidgets('shows a clear error for invalid credentials', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const WecomCheckinApp(
        config: WecomConfig(corpId: '', agentId: '', secret: ''),
      ),
    );
    await tester.enterText(find.byType(TextFormField).first, 'tospino');
    await tester.enterText(find.byType(TextFormField).last, 'incorrect');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.text('账号或密码错误，请重新输入'), findsOneWidget);
    expect(find.text('企业微信配置尚未完成'), findsNothing);
  });

  testWidgets('allows debug builds to skip authentication', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const WecomCheckinApp(
        config: WecomConfig(corpId: '', agentId: '', secret: ''),
      ),
    );
    await tester.tap(find.text('Debug 跳过登录'));
    await tester.pumpAndSettle();

    expect(find.text('Tospino-HR'), findsOneWidget);
    expect(find.text('企业微信配置尚未完成'), findsOneWidget);
  });
}
