// Képernyőképek készítése ellenőrzéshez:
//   flutter test tool/screenshots_test.dart --update-goldens
// A képek a tool/screens/ mappába kerülnek.
import 'dart:io';

import 'package:bullseye/data/store.dart';
import 'package:bullseye/engine/decode.dart';
import 'package:bullseye/engine/pipeline.dart';
import 'package:bullseye/engine/target.dart';
import 'package:bullseye/main.dart';
import 'package:bullseye/ui/home.dart';
import 'package:bullseye/ui/sheet_screen.dart';
import 'package:bullseye/ui/session_screen.dart';
import 'package:bullseye/ui/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

Future<void> _loadFonts() async {
  final reg = File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync();
  final bold = File('assets/fonts/NotoSans-Bold.ttf').readAsBytesSync();
  for (final fam in ['Roboto', 'NotoSans']) {
    final l = FontLoader(fam)
      ..addFont(Future.value(ByteData.view(reg.buffer)))
      ..addFont(Future.value(ByteData.view(bold.buffer)));
    await l.load();
  }
  // ikonok
  final iconPath = '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
  if (File(iconPath).existsSync()) {
    final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(File(iconPath).readAsBytesSync().buffer)));
    await l.load();
  }
}

void main() {
  late AppStore store;
  setUpAll(() async {
    await initializeDateFormatting('hu');
    Intl.defaultLocale = 'hu';
    await _loadFonts();
  });

  Future<void> setup(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.6;
    final dir = Directory.systemTemp.createTempSync('bullseye_shots');
    store = (await tester.runAsync(() => AppStore.open(dir: dir)))!;
    await tester.runAsync(() async {
      final session = store.newSession();
      for (final name in ['1_eredeti.png', '2_eredeti.png', '3_eredeti.png']) {
        final (rgb, _) = decodeForEngine(File('../testdata/$name').readAsBytesSync());
        final res = analyze(rgb, TargetSpec.mdlszGyorspont, expected: 15);
        final jpg = im.encodeJpg(im.Image.fromBytes(width: rgb.w, height: rgb.h, bytes: rgb.d.buffer, numChannels: 3));
        await store.addSheet(session, jpg, rgb.w, rgb.h, res.geometry.toJson(), [
          for (final s in res.shots) {'x': s.x, 'y': s.y, 'uncertain': s.uncertain, 'note': s.reason}
        ], 15);
      }
    });
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Widget app(Widget home, {Brightness b = Brightness.light}) => StoreScope(
        store: store,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light).copyWith(textTheme: buildTheme(Brightness.light).textTheme.apply(fontFamily: 'NotoSans')),
          darkTheme: buildTheme(Brightness.dark).copyWith(textTheme: buildTheme(Brightness.dark).textTheme.apply(fontFamily: 'NotoSans')),
          themeMode: b == Brightness.light ? ThemeMode.light : ThemeMode.dark,
          home: home,
        ),
      );

  testWidgets('kezdőképernyő', (tester) async {
    await setup(tester);
    await tester.pumpWidget(BullseyeApp(store: store));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screens/01_home.png'));
  });

  testWidgets('lap képernyő', (tester) async {
    await setup(tester);
    final sheet = store.sessions.first.sheets.first;
    await tester.pumpWidget(app(SheetScreen(sheet: sheet)));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screens/02_sheet.png'));
    // lövés kijelölése
    final s = sheet.shots[5];
    final box = tester.getRect(find.byType(InteractiveViewer));
    final fit = (box.width / sheet.imageW) < (box.height / sheet.imageH) ? box.width / sheet.imageW : box.height / sheet.imageH;
    final ox = box.left + (box.width - sheet.imageW * fit) / 2, oy = box.top + (box.height - sheet.imageH * fit) / 2;
    await tester.tapAt(Offset(ox + s.x * fit, oy + s.y * fit));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screens/03_sheet_selected.png'));
    await tester.tap(find.byTooltip('Táblázat és részletek'));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screens/04_details.png'));
  });

  testWidgets('edzés és statisztika', (tester) async {
    await setup(tester);
    await tester.pumpWidget(app(SessionScreen(session: store.sessions.first)));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screens/05_session.png'));
    await tester.pumpWidget(BullseyeApp(store: store));
    await settle(tester);
    await tester.tap(find.text('Statisztika').last);
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screens/06_stats.png'));
  });

  testWidgets('üres állapot sötét módban', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.6;
    store = (await tester.runAsync(() => AppStore.open(dir: Directory.systemTemp.createTempSync('b'))))!;
    await tester.pumpWidget(app(const HomeShell(), b: Brightness.dark));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screens/07_empty_dark.png'));
  });
}
