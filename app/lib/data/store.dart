// Helyi adattárolás: JSON fájlok és a lapfotók az app saját mappájában.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../engine/pipeline.dart';
import 'models.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

class AppStore extends ChangeNotifier {
  AppStore._(this._dir);

  final Directory _dir;
  final List<Session> sessions = [];
  AppSettings settings = AppSettings();

  static Future<AppStore> open({Directory? dir}) async {
    final base = dir ?? Directory(p.join((await getApplicationDocumentsDirectory()).path, 'bullseye'));
    await Directory(p.join(base.path, 'sheets')).create(recursive: true);
    final s = AppStore._(base);
    await s._load();
    return s;
  }

  File get _sessionsFile => File(p.join(_dir.path, 'sessions.json'));
  File get _settingsFile => File(p.join(_dir.path, 'settings.json'));
  String imagePathFor(String sheetId) => p.join(_dir.path, 'sheets', '$sheetId.jpg');
  String get exportDir => p.join(_dir.path, 'export');

  Future<void> _load() async {
    try {
      if (await _settingsFile.exists()) {
        settings = AppSettings.fromJson(jsonDecode(await _settingsFile.readAsString()) as Map<String, dynamic>);
      }
    } catch (_) {}
    try {
      if (await _sessionsFile.exists()) {
        final l = jsonDecode(await _sessionsFile.readAsString()) as List;
        sessions
          ..clear()
          ..addAll([
            for (final s in l) Session.fromJson((s as Map).cast<String, dynamic>(), specFor: settings.specFor)
          ]);
      }
    } catch (_) {}
    _sort();
  }

  void _sort() => sessions.sort((a, b) => b.date.compareTo(a.date));

  Future<void> save() async {
    final tmp = File('${_sessionsFile.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final s in sessions) s.toJson()]));
    await tmp.rename(_sessionsFile.path);
    await _settingsFile.writeAsString(jsonEncode(settings.toJson()));
  }

  /// Változás után: értesítés + mentés.
  Future<void> changed() async {
    _sort();
    notifyListeners();
    await save();
  }

  Future<void> updateSettings(AppSettings s) async {
    settings = s;
    for (final ses in sessions) {
      for (final sh in ses.sheets) {
        if (sh.geometry != null) sh.geometry = sh.geometry!.withSpec(settings.specFor(sh.targetId));
      }
    }
    await changed();
  }

  /// A mai edzés (ha nincs, létrehozza).
  Session todaySession() {
    final now = DateTime.now();
    for (final s in sessions) {
      if (s.date.year == now.year && s.date.month == now.month && s.date.day == now.day) return s;
    }
    final s = Session(id: newId(), date: now);
    sessions.add(s);
    _sort();
    return s;
  }

  Session newSession() {
    final s = Session(id: newId(), date: DateTime.now());
    sessions.add(s);
    _sort();
    return s;
  }

  Session? sessionOf(Sheet sheet) {
    for (final s in sessions) {
      if (s.sheets.contains(sheet)) return s;
    }
    return null;
  }

  Future<Sheet> addSheet(Session session, Uint8List jpeg, int w, int h, Map<String, dynamic>? geometry,
      List<Map<String, dynamic>> shots, int expected) async {
    final id = newId();
    final path = imagePathFor(id);
    await File(path).writeAsBytes(jpeg);
    final spec = settings.spec;
    final sheet = Sheet(
      id: id,
      createdAt: DateTime.now(),
      imagePath: path,
      imageW: w,
      imageH: h,
      expectedShots: expected,
      targetId: spec.id,
      geometry: geometry == null ? null : TargetGeometry.fromJson(geometry, spec: spec),
      shots: [
        for (final s in shots)
          Shot(
            id: newId(),
            x: (s['x'] as num).toDouble(),
            y: (s['y'] as num).toDouble(),
            uncertain: s['uncertain'] as bool? ?? false,
            detectNote: s['note'] as String? ?? '',
          )
      ],
    );
    session.sheets.add(sheet);
    await changed();
    return sheet;
  }

  Future<void> deleteSheet(Sheet sheet) async {
    final s = sessionOf(sheet);
    s?.sheets.remove(sheet);
    if (s != null && s.sheets.isEmpty) sessions.remove(s);
    try {
      await File(sheet.imagePath).delete();
    } catch (_) {}
    await changed();
  }

  Future<void> deleteSession(Session s) async {
    for (final sh in s.sheets) {
      try {
        await File(sh.imagePath).delete();
      } catch (_) {}
    }
    sessions.remove(s);
    await changed();
  }

  /// Minden lap időrendben (régebbi elöl).
  List<(Session, Sheet)> allSheetsChronological() {
    final out = <(Session, Sheet)>[];
    for (final s in sessions) {
      for (final sh in s.sheets) {
        out.add((s, sh));
      }
    }
    out.sort((a, b) => a.$2.createdAt.compareTo(b.$2.createdAt));
    return out;
  }
}

/// Az [AppStore] elérése a widgetfából.
class StoreScope extends InheritedNotifier<AppStore> {
  const StoreScope({super.key, required AppStore store, required super.child}) : super(notifier: store);

  static AppStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}
