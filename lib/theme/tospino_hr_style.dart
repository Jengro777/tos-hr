import 'package:material_ui/material_ui.dart';

abstract final class TospinoHrColors {
  static const brand = Color(0xFFC43D28);
  static const brandLight = Color(0xFFE05A43);
  static const brandTint = Color(0xFFFDECE8);
  static const brandTintBorder = Color(0xFFF5CEC5);
  static const ink = Color(0xFF1C1C1C);
  static const ink2 = Color(0xFF444442);
  static const ink3 = Color(0xFF5E5E5C);
  static const ink4 = Color(0xFF92918E);
  static const surface = Color(0xFFFFFFFF);
  static const background = Color(0xFFF7F7F5);
  static const surfaceMuted = Color(0xFFF1F0EE);
  static const line = Color(0xFFE4E3E0);
  static const lineSoft = Color(0xFFEFEEEC);
  static const success = Color(0xFF1E7A54);
  static const successTint = Color(0xFFE4F2EA);
  static const warning = Color(0xFF8A5B08);
  static const warningTint = Color(0xFFFAF0DC);
  static const warningBorder = Color(0xFFEFDCB4);
  static const danger = Color(0xFF8E2E22);
  static const dangerTint = Color(0xFFF7E4E0);
  static const dangerBorder = Color(0xFFE8BDB4);
  static const info = Color(0xFF355D7A);
  static const infoTint = Color(0xFFE8EFF3);
}

abstract final class TospinoHrText {
  static const pageTitle = TextStyle(
    color: TospinoHrColors.ink,
    fontSize: 24,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.7,
    height: 1.18,
  );

  static const cardTitle = TextStyle(
    color: TospinoHrColors.ink,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.35,
  );

  static const body = TextStyle(
    color: TospinoHrColors.ink2,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const meta = TextStyle(
    color: TospinoHrColors.ink3,
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static const eyebrow = TextStyle(
    color: TospinoHrColors.ink4,
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.9,
    height: 1.3,
  );

  static const number = TextStyle(
    color: TospinoHrColors.ink,
    fontSize: 18,
    fontWeight: FontWeight.w800,
    height: 1.05,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

abstract final class TospinoHrShadows {
  static const card = <BoxShadow>[
    BoxShadow(color: Color(0x081C1C1C), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(
      color: Color(0x101C1C1C),
      offset: Offset(0, 8),
      blurRadius: 24,
      spreadRadius: -14,
    ),
  ];
}
