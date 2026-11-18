// Retró műszerfal stílus: sötét vászon, krém/barnásszürke panelek,
// narancs kiemelés; sárga és korall jelzőszínek.
import 'package:material_ui/material_ui.dart';

// Paletta
const Color kInk = Color(0xFF16110B); // vászon, sötét szöveg a paneleken
const Color kRaised = Color(0xFF241D16); // egy lépéssel világosabb felület
const Color kCream = Color(0xFFF6EFD5);
const Color kTaupe = Color(0xFFA5937D);
const Color kOrange = Color(0xFFEA7D54); // egyetlen műveleti kiemelőszín
const Color kYellow = Color(0xFFF6BE67);
const Color kCoral = Color(0xFFF05462);

/// Megjelenítési alapszín (régi név, a meglévő kód miatt).
const Color kAccent = kOrange;

/// Jelölőszínek a lapon (fekete és fehér célterületen is látszanak,
/// sötét kontúrral rajzolva).
const Color kShotColor = kCoral; // normál találat
const Color kCheckColor = kYellow; // nézőkével ellenőrizendő
const Color kSelectedColor = Color(0xFF7FD3F0); // kijelölt (jól elválik a többitől)
const Color kEditedColor = kCream; // kézzel javított

const String kFont = 'SpaceGrotesk';

/// Panel tónusok a statisztikai csempékhez, körbeforgatva.
const List<Color> kPanelTones = [kOrange, kYellow, kCream, kTaupe];

ThemeData buildTheme([Brightness _ = Brightness.dark]) {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: kOrange,
    onPrimary: kInk,
    primaryContainer: Color(0xFF4A2A1C),
    onPrimaryContainer: kCream,
    secondary: kYellow,
    onSecondary: kInk,
    secondaryContainer: Color(0xFF3A2E1C),
    onSecondaryContainer: kCream,
    tertiary: kCoral,
    onTertiary: kInk,
    tertiaryContainer: kCoral,
    onTertiaryContainer: kInk,
    error: kCoral,
    onError: kInk,
    surface: kInk,
    onSurface: kCream,
    onSurfaceVariant: Color(0xFFBFB09C),
    surfaceContainerLowest: Color(0xFF110D08),
    surfaceContainerLow: kRaised,
    surfaceContainer: kRaised,
    surfaceContainerHigh: Color(0xFF2E261D),
    surfaceContainerHighest: Color(0xFF3A3026),
    outline: kTaupe,
    outlineVariant: Color(0xFF4A3F33),
    inverseSurface: kCream,
    onInverseSurface: kInk,
    inversePrimary: Color(0xFFB4532E),
    shadow: Colors.black,
    scrim: Colors.black,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: kFont);
  final tt = base.textTheme.apply(bodyColor: kCream, displayColor: kCream, fontFamily: kFont);
  final border = kTaupe.withValues(alpha: 0.22);
  const pill = StadiumBorder();
  return base.copyWith(
    textTheme: tt.copyWith(
      headlineSmall: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w500),
      titleLarge: tt.titleLarge?.copyWith(fontWeight: FontWeight.w500),
      titleMedium: tt.titleMedium?.copyWith(fontWeight: FontWeight.w500),
    ),
    scaffoldBackgroundColor: kInk,
    cardTheme: CardThemeData(
      elevation: 0,
      color: kRaised,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: border)),
    ),
    dividerTheme: DividerThemeData(color: border, space: 1, thickness: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: kInk,
      foregroundColor: kCream,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: tt.titleLarge?.copyWith(fontWeight: FontWeight.w500, color: kCream),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kInk,
      indicatorColor: kOrange,
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith((s) =>
          IconThemeData(color: s.contains(WidgetState.selected) ? kInk : const Color(0xFFBFB09C))),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => tt.labelMedium?.copyWith(
          color: s.contains(WidgetState.selected) ? kCream : const Color(0xFFBFB09C),
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kOrange,
      foregroundColor: kInk,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: pill,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kOrange,
        foregroundColor: kInk,
        minimumSize: const Size(48, 48),
        shape: pill,
        textStyle: const TextStyle(fontFamily: kFont, fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kCream,
        side: const BorderSide(color: kTaupe),
        minimumSize: const Size(48, 48),
        shape: pill,
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: kOrange, minimumSize: const Size(48, 48))),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kCream : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kInk : kCream),
        side: const WidgetStatePropertyAll(BorderSide(color: kTaupe)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: kRaised, surfaceTintColor: Colors.transparent),
    dialogTheme: const DialogThemeData(backgroundColor: kRaised, surfaceTintColor: Colors.transparent),
    popupMenuTheme: const PopupMenuThemeData(color: kRaised, surfaceTintColor: Colors.transparent),
    listTileTheme: const ListTileThemeData(iconColor: kTaupe),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kInk : kTaupe),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kOrange : kRaised),
    ),
    sliderTheme: const SliderThemeData(activeTrackColor: kOrange, thumbColor: kOrange, inactiveTrackColor: Color(0xFF4A3F33)),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: kOrange),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kCream,
      contentTextStyle: tt.bodyMedium?.copyWith(color: kInk),
      actionTextColor: const Color(0xFFB4532E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

/// Sötét tinta a színes paneleken.
Color inkOn(Color panel) => panel.computeLuminance() > 0.25 ? kInk : kCream;
