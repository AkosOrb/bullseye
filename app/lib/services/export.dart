// Export: jelölt kép (PNG) és PDF, megosztás.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';
import '../data/stats.dart';
import '../data/store.dart';
import 'download.dart';
import '../ui/sheet_painter.dart';
import '../ui/widgets.dart';

/// A lap fotója a jelölésekkel és a fejléccel, PNG-ként.
Future<Uint8List> renderSheetPng(AppStore store, Sheet sheet) async {
  final bytes = await store.imageBytes(sheet);
  if (bytes == null) throw StateError('A lap fotója nem található.');
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final img = frame.image;
  final w = img.width.toDouble(), h = img.height.toDouble();
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec, Rect.fromLTWH(0, 0, w, h));
  canvas.drawImage(img, Offset.zero, Paint());
  final views = sheet.views();
  final scale = (w < h ? w : h) / 700.0;
  SheetPainter(
    views: views,
    imageSize: Size(w, h),
    pelletRadius: sheet.geometry?.pelletRadiusOrig ?? 10,
    labelScale: scale,
  ).paint(canvas, Size(w, h));
  // fejléc
  final total = views.fold<int>(0, (a, v) => a + v.score);
  final tp = TextPainter(
    text: TextSpan(
      text: '${views.length} lövés – összesen: $total pont',
      style: TextStyle(color: const Color(0xFF111111), fontSize: 20 * scale, fontWeight: FontWeight.w700),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final box = Rect.fromLTWH(10 * scale, 10 * scale, tp.width + 24 * scale, tp.height + 14 * scale);
  canvas.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(6 * scale)), Paint()..color = Colors.white.withValues(alpha: 0.95));
  canvas.drawRRect(
      RRect.fromRectAndRadius(box, Radius.circular(6 * scale)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * scale
        ..color = const Color(0xFF333333));
  tp.paint(canvas, box.topLeft + Offset(12 * scale, 7 * scale));
  final pic = rec.endRecording();
  final out = await pic.toImage(img.width, img.height);
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<pw.ThemeData> _pdfTheme() async {
  final reg = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
  return pw.ThemeData.withFont(base: reg, bold: bold);
}

pw.Widget _sheetBlock(Sheet sheet, Uint8List png, String title) {
  final views = sheet.views();
  final total = views.fold<int>(0, (a, v) => a + v.score);
  final dist = ringDistribution(views);
  final sorted = [...views]..sort((a, b) => b.score.compareTo(a.score));
  final checks = views.where((v) => v.needsCheck).toList();
  return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    pw.Text(sheet.shooter.isNotEmpty ? '$title – ${sheet.shooter}' : title,
        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
    pw.SizedBox(height: 4),
    pw.Text('${views.length} lövés (megadott: ${sheet.expectedShots}) – összesen $total pont'
        '${sheet.irregular ? ' – nem szabályos (szabályosan ${sheet.regulationShots} lövés)' : ''}'),
    pw.SizedBox(height: 10),
    pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Expanded(flex: 3, child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain, height: 430)),
      pw.SizedBox(width: 14),
      pw.Expanded(
        flex: 2,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Lövések gyűrűnként', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: ['Pont', 'Lövés'],
            data: [for (final d in dist) ['${d.score}', '${d.count}']],
            cellAlignment: pw.Alignment.centerRight,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          ),
          pw.SizedBox(height: 10),
          if (sorted.isNotEmpty) ...[
            pw.Text('Legjobb: ${sorted.first.score} pont (${sorted.first.index}. lövés)'),
            pw.Text('Leggyengébb: ${sorted.last.score} pont (${sorted.last.index}. lövés)'),
          ],
          if (checks.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text('Nézőkével ellenőrizendő', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            for (final c in checks) pw.Text('${c.index}. lövés: ${c.score} pont – ${c.note}', style: const pw.TextStyle(fontSize: 9)),
          ],
        ]),
      ),
    ]),
  ]);
}

Future<void> _share(BuildContext context, Uint8List bytes, String name, String mime, String text) async {
  final box = context.findRenderObject() as RenderBox?;
  try {
    final r = await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: mime, name: name)],
      fileNameOverrides: [name],
      text: text,
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ));
    if (r.status != ShareResultStatus.unavailable) return;
  } catch (_) {
    if (!canDownload) rethrow;
  }
  // Böngészőben, ha a megosztás nem érhető el: letöltés.
  if (canDownload) downloadBytes(bytes, name, mime);
}

String _stamp(DateTime d) =>
    '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}_${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}';

Future<void> shareSheetImage(BuildContext context, Sheet sheet) async {
  final png = await renderSheetPng(StoreScope.of(context), sheet);
  if (context.mounted) {
    await _share(context, png, 'lolap_${_stamp(sheet.createdAt)}.png', 'image/png', 'Lőlap: ${sheet.total} pont');
  }
}

Future<void> shareSheetPdf(BuildContext context, Sheet sheet) async {
  final store = StoreScope.of(context);
  final theme = await _pdfTheme();
  final png = await renderSheetPng(store, sheet);
  final doc = pw.Document(theme: theme, title: 'Lőlap ${fmtShortDate(sheet.createdAt)}');
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(24),
    build: (_) => _sheetBlock(sheet, png, '${sheet.name.isNotEmpty ? sheet.name : 'Lőlap'} – ${fmtDate(sheet.createdAt)} ${fmtTime(sheet.createdAt)}'),
  ));
  final pdf = await doc.save();
  if (context.mounted) {
    await _share(context, pdf, 'lolap_${_stamp(sheet.createdAt)}.pdf', 'application/pdf', 'Lőlap: ${sheet.total} pont');
  }
}

Future<void> shareSessionPdf(BuildContext context, Session session) async {
  final store = StoreScope.of(context);
  final theme = await _pdfTheme();
  final sheets = [...session.sheets]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final doc = pw.Document(theme: theme, title: 'Edzés ${fmtShortDate(session.date)}');
  final title = session.title.isNotEmpty ? session.title : fmtDate(session.date);
  final group = groupStats([for (final s in sheets) ...shotOffsets(s)]);
  final rank = shooterRanking(sheets);
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Edzés: $title', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 8),
      pw.Text('${sheets.length} lap, ${session.shotCount} lövés – összesen ${session.total} pont'),
      pw.Text('Átlag: ${fmtNum(session.averagePerSheet)} pont/lap, ${fmtNum(session.averagePerShot, 2)} pont/lövés'),
      if (group != null) pw.Text('Szórásminta: ${group.describe()} Átlagos szórás: ${fmtNum(group.spread, 0)} mm.'),
      if (rank.length >= 2) ...[
        pw.SizedBox(height: 16),
        pw.Text('Rangsor', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: ['Hely', 'Lövő', 'Lap', 'Legjobb', 'Összesen'],
          data: [
            for (var i = 0; i < rank.length; i++)
              ['${i + 1}.', rank[i].name, '${rank[i].sheets}', '${rank[i].best}', '${rank[i].total}']
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellAlignments: {2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight},
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        ),
      ],
      pw.SizedBox(height: 16),
      pw.TableHelper.fromTextArray(
        headers: ['Lap', 'Lövő', 'Idő', 'Lövés', 'Pont'],
        data: [
          for (var i = 0; i < sheets.length; i++)
            [sheetTitle(sheets[i], i + 1), sheets[i].shooter, fmtTime(sheets[i].createdAt), '${sheets[i].shots.length}', '${sheets[i].total}']
        ],
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        cellAlignments: {3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight},
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      ),
    ]),
  ));
  for (var i = 0; i < sheets.length; i++) {
    final png = await renderSheetPng(store, sheets[i]);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => _sheetBlock(sheets[i], png, '${sheetTitle(sheets[i], i + 1)} – ${fmtTime(sheets[i].createdAt)}'),
    ));
  }
  final pdf = await doc.save();
  if (context.mounted) {
    await _share(context, pdf, 'edzes_${_stamp(session.date)}.pdf', 'application/pdf', 'Edzés: ${session.total} pont');
  }
}
