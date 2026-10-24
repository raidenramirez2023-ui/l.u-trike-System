import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// LuTrike design system.
///
/// One light palette for every portal (landing, student, driver, admin).
/// Neutrals follow a cool gray scale; the brand color is a deep emerald that
/// passes WCAG AA on white for text and buttons. Semantic colors are reserved
/// for state (success / warning / danger / info) and never used decoratively.
class AppColors {
  // Surfaces
  static const canvas = Color(0xFFF6F7F9);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceElevated = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF2F4F7);
  static const surfaceHighlight = Color(0xFFECFDF5);

  // Text
  static const ink = Color(0xFF101828);
  static const inkSecondary = Color(0xFF475467);
  static const inkMuted = Color(0xFF667085);
  static const inkDisabled = Color(0xFF98A2B3);
  static const inkSoft = inkSecondary;
  static const muted = inkMuted;

  // Borders
  static const border = Color(0xFFE4E7EC);
  static const borderSubtle = Color(0xFFF2F4F7);
  static const borderStrong = Color(0xFFD0D5DD);
  static const borderHighlight = Color(0xFF059669);

  // Brand (emerald)
  static const primary = Color(0xFF047857); // 5.5:1 on white
  static const primaryDark = Color(0xFF065F46);
  static const primaryDeep = Color(0xFF064E3B);
  static const primaryLight = Color(0xFF10B981); // charts, dots, map markers
  static const primarySoft = Color(0xFFECFDF5);
  static const primaryMuted = Color(0xFFD1FAE5);
  static const primaryGlow = Color(0x1F047857);

  // Accent — used for "special / solo trip" and ranking highlights
  static const accent = Color(0xFFB54708);
  static const accentSoft = Color(0xFFFFFAEB);
  static const accentDark = Color(0xFF93370D);

  // Semantic
  static const success = Color(0xFF067647);
  static const successSoft = Color(0xFFECFDF3);
  static const warning = Color(0xFFB54708);
  static const warningSoft = Color(0xFFFFFAEB);
  static const warningBorder = Color(0xFFFEDF89);
  static const danger = Color(0xFFD92D20);
  static const dangerSoft = Color(0xFFFEF3F2);
  static const dangerBorder = Color(0xFFFECDCA);
  static const info = Color(0xFF175CD3);
  static const infoSoft = Color(0xFFEFF8FF);
  static const cyan = Color(0xFF0E7090);

  // Gradients are kept for API compatibility but are intentionally near-flat.
  static const brandGradient = LinearGradient(
    colors: [Color(0xFF047857), Color(0xFF065F46)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Deep brand panel used behind white text (auth side panel, landing hero).
  static const meshHeroGradient = LinearGradient(
    colors: [Color(0xFF053B2E), Color(0xFF042F25)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const heroGradient = meshHeroGradient;

  static const cardGlow = LinearGradient(colors: [Colors.white, Colors.white]);

  static const accentGradient = LinearGradient(colors: [Color(0xFFB54708), Color(0xFF93370D)]);
}

/// Kept so existing screens continue to compile; every value maps onto the
/// single [AppColors] palette so all portals share one visual language.
class StudentColors {
  static const canvas = AppColors.canvas;
  static const surface = AppColors.surface;
  static const surfaceElevated = AppColors.surfaceElevated;
  static const surfaceHighlight = AppColors.surfaceHighlight;
  static const surfaceMuted = AppColors.surfaceMuted;

  static const ink = AppColors.ink;
  static const inkSecondary = AppColors.inkSecondary;
  static const inkMuted = AppColors.inkMuted;
  static const inkSoft = AppColors.inkSoft;
  static const muted = AppColors.muted;

  static const border = AppColors.border;
  static const borderSubtle = AppColors.borderSubtle;
  static const borderHighlight = AppColors.borderHighlight;

  static const primary = AppColors.primary;
  static const primaryDark = AppColors.primaryDark;
  static const primaryDeep = AppColors.primaryDeep;
  static const primaryLight = AppColors.primaryLight;
  static const primarySoft = AppColors.primarySoft;
  static const primaryGlow = AppColors.primaryGlow;

  static const accent = AppColors.accent;
  static const accentSoft = AppColors.accentSoft;
  static const accentDark = AppColors.accentDark;

  static const danger = AppColors.danger;
  static const dangerSoft = AppColors.dangerSoft;
  static const warning = AppColors.warning;
  static const warningSoft = AppColors.warningSoft;
  static const info = AppColors.info;
  static const infoSoft = AppColors.infoSoft;
  static const success = AppColors.success;
  static const successSoft = AppColors.successSoft;

  static const brandGradient = AppColors.brandGradient;
}

/// Corner radius scale. Cards 12, controls 8, badges 6, pill 999.
class AppRadius {
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double full = 999;
}

/// 4pt spacing scale.
class AppSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Restrained elevation: a hairline shadow for resting cards, a soft lift for
/// hover/overlays. No colored glows.
class AppShadows {
  static const subtle = card;

  static const card = [
    BoxShadow(color: Color(0x0D101828), blurRadius: 2, offset: Offset(0, 1)),
  ];

  static const cardHover = [
    BoxShadow(color: Color(0x14101828), blurRadius: 8, offset: Offset(0, 4), spreadRadius: -2),
    BoxShadow(color: Color(0x0A101828), blurRadius: 4, offset: Offset(0, 2), spreadRadius: -2),
  ];

  static const overlay = [
    BoxShadow(color: Color(0x14101828), blurRadius: 16, offset: Offset(0, 12), spreadRadius: -4),
    BoxShadow(color: Color(0x08101828), blurRadius: 6, offset: Offset(0, 4), spreadRadius: -2),
  ];

  static const buttonPrimary = [
    BoxShadow(color: Color(0x0D101828), blurRadius: 2, offset: Offset(0, 1)),
  ];

  static const buttonDanger = buttonPrimary;
}

class StudentShadows {
  static const card = AppShadows.card;
  static const cardHover = AppShadows.cardHover;
  static const buttonPrimary = AppShadows.buttonPrimary;
  static const primaryGlow = AppShadows.card;
}

/// Typography tokens (Inter). Use these for page-level hierarchy.
class AppText {
  static const pageTitle = TextStyle(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.4, color: AppColors.ink, height: 1.25);
  static const sectionTitle = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.1, color: AppColors.ink, height: 1.35);
  static const body = TextStyle(fontSize: 14, color: AppColors.inkSecondary, height: 1.45);
  static const caption = TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4);
  static const label = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.inkMuted, letterSpacing: 0.1);
  static const overline = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.inkMuted, letterSpacing: 0.6);
  static const metric = TextStyle(fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: -0.6, color: AppColors.ink, height: 1.15);
}

ThemeData buildTheme() {
  const scheme = ColorScheme.light(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: AppColors.primarySoft,
    onPrimaryContainer: AppColors.primaryDark,
    secondary: AppColors.primary,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.surfaceMuted,
    onSecondaryContainer: AppColors.ink,
    tertiary: AppColors.accent,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.inkSecondary,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: AppColors.canvas,
    surfaceContainer: AppColors.surfaceMuted,
    surfaceContainerHigh: AppColors.surfaceMuted,
    surfaceContainerHighest: AppColors.border,
    outline: AppColors.borderStrong,
    outlineVariant: AppColors.border,
    error: AppColors.danger,
    onError: Colors.white,
    errorContainer: AppColors.dangerSoft,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.canvas,
    splashFactory: InkRipple.splashFactory,
    hoverColor: const Color(0x08101828),
    focusColor: const Color(0x1F047857),
    highlightColor: Colors.transparent,
    visualDensity: VisualDensity.standard,
  );

  final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
    bodyColor: AppColors.ink,
    displayColor: AppColors.ink,
  );

  final controlShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md));
  final labelStyle = GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, letterSpacing: 0);

  OutlineInputBorder inputBorder(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: c, width: w),
      );

  return base.copyWith(
    textTheme: textTheme.copyWith(
      displaySmall: textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -1.0),
      headlineMedium: textTheme.headlineMedium?.copyWith(fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: -0.6),
      headlineSmall: textTheme.headlineSmall?.copyWith(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.4),
      titleLarge: textTheme.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.2),
      titleMedium: textTheme.titleMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.1),
      titleSmall: textTheme.titleSmall?.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
      bodyLarge: textTheme.bodyLarge?.copyWith(fontSize: 15, height: 1.5),
      bodyMedium: textTheme.bodyMedium?.copyWith(fontSize: 14, height: 1.45, color: AppColors.inkSecondary),
      bodySmall: textTheme.bodySmall?.copyWith(fontSize: 12.5, color: AppColors.inkMuted),
      labelLarge: textTheme.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      labelMedium: textTheme.labelMedium?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w500),
      labelSmall: textTheme.labelSmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.2),
    ),
    iconTheme: const IconThemeData(color: AppColors.inkSecondary, size: 20),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      iconTheme: const IconThemeData(color: AppColors.inkSecondary, size: 20),
      actionsIconTheme: const IconThemeData(color: AppColors.inkSecondary, size: 20),
      shape: const Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      titleTextStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink, letterSpacing: -0.1),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      labelStyle: const TextStyle(color: AppColors.inkSecondary, fontSize: 14, fontWeight: FontWeight.w400),
      floatingLabelStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w500),
      hintStyle: const TextStyle(color: AppColors.inkDisabled, fontSize: 14),
      helperStyle: const TextStyle(color: AppColors.inkMuted, fontSize: 12.5),
      errorStyle: const TextStyle(color: AppColors.danger, fontSize: 12.5, fontWeight: FontWeight.w500),
      prefixIconColor: WidgetStateColor.resolveWith(
        (s) => s.contains(WidgetState.focused) ? AppColors.primary : AppColors.inkMuted,
      ),
      suffixIconColor: AppColors.inkMuted,
      border: inputBorder(AppColors.borderStrong),
      enabledBorder: inputBorder(AppColors.borderStrong),
      focusedBorder: inputBorder(AppColors.primary, 1.5),
      errorBorder: inputBorder(AppColors.danger),
      focusedErrorBorder: inputBorder(AppColors.danger, 1.5),
      disabledBorder: inputBorder(AppColors.border),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: controlShape,
        elevation: 0,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.surfaceMuted,
        disabledForegroundColor: AppColors.inkDisabled,
        textStyle: labelStyle,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: controlShape,
        elevation: 0,
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        textStyle: labelStyle,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: controlShape,
        side: const BorderSide(color: AppColors.borderStrong, width: 1),
        foregroundColor: AppColors.ink,
        backgroundColor: AppColors.surface,
        textStyle: labelStyle,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        shape: controlShape,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        textStyle: labelStyle,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.inkSecondary,
        shape: controlShape,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xs)),
      side: const BorderSide(color: AppColors.borderStrong, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : Colors.transparent),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.borderStrong),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.primarySoft,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.inkSecondary),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: const Color(0x33101828),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      titleTextStyle: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink, letterSpacing: -0.2),
      contentTextStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.inkSecondary, height: 1.5),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: AppColors.borderStrong,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      elevation: 4,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(AppRadius.sm)),
      textStyle: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      waitDuration: const Duration(milliseconds: 400),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: const Color(0x33101828),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.border),
      ),
      textStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.ink),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.ink),
      menuStyle: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(AppColors.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md))),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: AppColors.inkMuted,
      titleTextStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.ink),
      subtitleTextStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.inkMuted),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.primarySoft,
      height: 64,
      elevation: 0,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(size: 22, color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.inkMuted),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => GoogleFonts.inter(
          fontSize: 11.5,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? AppColors.ink : AppColors.inkMuted,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primarySoft,
      selectedIconTheme: const IconThemeData(color: AppColors.primary, size: 22),
      unselectedIconTheme: const IconThemeData(color: AppColors.inkMuted, size: 22),
      selectedLabelTextStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink),
      unselectedLabelTextStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.inkMuted),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.ink,
      unselectedLabelColor: AppColors.inkMuted,
      indicatorColor: AppColors.primary,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: AppColors.border,
      labelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      unselectedLabelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
      overlayColor: const WidgetStatePropertyAll(Color(0x08101828)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: AppColors.surfaceMuted,
      circularTrackColor: Colors.transparent,
    ),
    badgeTheme: const BadgeThemeData(backgroundColor: AppColors.danger, textColor: Colors.white),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(AppColors.inkDisabled.withValues(alpha: 0.5)),
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(6),
    ),
  );
}

/// All portals share the same theme now; kept for existing call sites.
ThemeData buildStudentTheme() => buildTheme();
