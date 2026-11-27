import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'config/app_runtime_config.dart';
import 'config/sync_api_config.dart';
import 'config/wecom_config.dart';
import 'data/attendance_database.dart';
import 'data/attendance_database_factory.dart';
import 'screens/checkin_page.dart';
import 'screens/login_page.dart';
import 'services/wecom_api_client.dart';
import 'theme/tospino_hr_style.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final runtimeConfig = await loadAppRuntimeConfig();
  runApp(
    WecomCheckinApp(
      config: runtimeConfig.wecom,
      database: createAttendanceDatabase(config: runtimeConfig.database),
      syncApiConfig: runtimeConfig.syncApi,
    ),
  );
}

class WecomCheckinApp extends StatefulWidget {
  const WecomCheckinApp({
    super.key,
    required this.config,
    this.apiClient,
    this.database,
    this.syncApiConfig = const SyncApiConfig(),
    this.initialAuthenticated = false,
  });

  final WecomConfig config;
  final WeComApiClient? apiClient;
  final AttendanceDatabase? database;
  final SyncApiConfig syncApiConfig;
  final bool initialAuthenticated;

  @override
  State<WecomCheckinApp> createState() => _WecomCheckinAppState();
}

class _WecomCheckinAppState extends State<WecomCheckinApp> {
  late bool _authenticated;

  @override
  void initState() {
    super.initState();
    _authenticated = widget.initialAuthenticated;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: TospinoHrColors.brand,
      brightness: Brightness.light,
      primary: TospinoHrColors.brand,
      surface: TospinoHrColors.surface,
    );

    return MaterialApp(
      title: 'Tospino-HR',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: TospinoHrColors.background,
        fontFamilyFallback: const [
          'PingFang SC',
          'Microsoft YaHei',
          'Noto Sans CJK SC',
        ],
        textTheme: const TextTheme(
          headlineSmall: TospinoHrText.pageTitle,
          titleLarge: TospinoHrText.cardTitle,
          titleMedium: TospinoHrText.cardTitle,
          bodyLarge: TospinoHrText.body,
          bodyMedium: TospinoHrText.body,
          bodySmall: TospinoHrText.meta,
          labelLarge: TextStyle(
            color: TospinoHrColors.ink,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        dividerColor: TospinoHrColors.lineSoft,
        datePickerTheme: const DatePickerThemeData(
          backgroundColor: TospinoHrColors.surface,
          headerBackgroundColor: TospinoHrColors.ink,
          headerForegroundColor: Colors.white,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: TospinoHrColors.ink,
          contentTextStyle: const TextStyle(
            color: TospinoHrColors.surface,
            fontSize: 13,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: TospinoHrColors.surfaceMuted,
          hintStyle: TospinoHrText.meta.copyWith(color: TospinoHrColors.ink4),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: TospinoHrColors.brand,
              width: 1.2,
            ),
          ),
        ),
      ),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: _authenticated
          ? CheckinPage(
              config: widget.config,
              apiClient: widget.apiClient,
              database: widget.database,
              syncApiConfig: widget.syncApiConfig,
            )
          : LoginPage(
              allowDebugSkip: kDebugMode,
              onAuthenticated: () {
                setState(() => _authenticated = true);
              },
            ),
    );
  }
}
