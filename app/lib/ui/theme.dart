import 'package:material_ui/material_ui.dart';

/// Egyetlen kiemelőszín (kék) a műveletekhez; minden más semleges.
const Color kAccent = Color(0xFF1D5FA8);

/// Jelölőszínek a lapon (fekete és fehér háttéren is jól látszanak).
const Color kShotColor = Color(0xFFE53935); // normál találat
const Color kCheckColor = Color(0xFFFFA000); // nézőkével ellenőrizendő
const Color kSelectedColor = Color(0xFF29B6F6); // kijelölt
const Color kEditedColor = Color(0xFF43A047); // kézzel javított

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: kAccent, brightness: b, dynamicSchemeVariant: DynamicSchemeVariant.neutral)
      .copyWith(primary: b == Brightness.light ? kAccent : const Color(0xFF8DB8F0));
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: b);
  final border = scheme.outlineVariant.withValues(alpha: 0.6);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border),
      ),
    ),
    dividerTheme: DividerThemeData(color: border, space: 1, thickness: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
