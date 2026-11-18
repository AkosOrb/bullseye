import 'dart:io';

import 'package:bullseye/data/models.dart';
import 'package:bullseye/data/stats.dart';
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
    final store = await tester.runAsync(() => AppStore.open(dir: dir.path));
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

  test('lap neve és lövője mentődik, rangsor lövőnként', () {
    Sheet mk(String shooter, int pts) => Sheet(
          id: '$shooter$pts',
          createdAt: DateTime(2026, 11, 18),
          imagePath: '',
          imageW: 10,
          imageH: 10,
          expectedShots: 1,
          geometry: null,
          targetId: 'mdlsz_gyorspont',
          shots: [Shot(id: 'x', x: 0, y: 0, override: pts)],
          shooter: shooter,
        );
    final a = mk('Anna', 10)..name = 'Döntő';
    final back = Sheet.fromJson(a.toJson());
    expect(back.name, 'Döntő');
    expect(back.shooter, 'Anna');
    final r = shooterRanking([a, mk('Bence', 12), mk('Anna', 5), mk('', 13)]);
    expect([for (final x in r) x.name], ['Anna', 'Bence']);
    expect(r.first.total, 15);
    expect(r.first.sheets, 2);
  });
}
