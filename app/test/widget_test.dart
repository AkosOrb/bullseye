import 'dart:io';

import 'package:bullseye/data/models.dart';
import 'package:bullseye/data/store.dart';
import 'package:bullseye/main.dart';
import 'package:bullseye/ui/sheet_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('hu');
    Intl.defaultLocale = 'hu';
  });

  testWidgets('üres kezdőképernyő: cím, magyarázat és fotózás gomb', (tester) async {
    final dir = Directory.systemTemp.createTempSync('bullseye_test');
    final store = await tester.runAsync(() => AppStore.open(dir: dir));
    await tester.pumpWidget(BullseyeApp(store: store!));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Még nincs kiértékelt lap'), findsOneWidget);
    expect(find.text('Lap fotózása'), findsWidgets);
    expect(find.text('Edzések'), findsWidgets);
  });

  testWidgets('részletek táblázat: gyűrűnkénti eloszlás és legjobb lövés', (tester) async {
    final shots = [
      Shot(id: 'a', x: 0, y: 0, override: 10),
      Shot(id: 'b', x: 0, y: 0, override: 10),
      Shot(id: 'c', x: 0, y: 0, override: 7),
    ];
    final views = [for (var i = 0; i < shots.length; i++) ShotView(shots[i], i + 1, null)];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SheetDetails(views: views))));
    expect(find.text('27'), findsOneWidget); // összesen
    expect(find.text('10 pont'), findsWidgets);
    expect(find.text('2 lövés'), findsOneWidget);
  });
}
