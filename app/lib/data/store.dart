// Helyi adattárolás: JSON és a lapfotók (telefonon fájlok, böngészőben IndexedDB).
import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../engine/pipeline.dart';
import 'blobs.dart';
import 'models.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

class AppStore extends ChangeNotifier {
  AppStore._(this._blobs);

  final Blobs _blobs;
  final List<Session> sessions = [];
  AppSettings settings = AppSettings();
  final Map<String, Future<Uint8List?>> _images = {};

  static const _sessionsKey = 'sessions.json';
  static const _settingsKey = 'settings.json';

  /// [dir]: a tároló mappája (teszthez); böngészőben nincs jelentősége.
  static Future<AppStore> open({String? dir}) async {
    final s = AppStore._(await openBlobs(dir: dir));
    await s._load();
    return s;
  }

  /// A lap fotója (gyorsítótárazva).
  Future<Uint8List?> imageBytes(Sheet sheet) =>
      _images.putIfAbsent(sheet.imagePath, () => _blobs.readBytes(sheet.imagePath));

  Future<void> _load() async {
    try {
      final t = await _blobs.readText(_settingsKey);
      if (t != null) settings = AppSettings.fromJson(jsonDecode(t) as Map<String, dynamic>);
    } catch (_) {}
    try {
      final t = await _blobs.readText(_sessionsKey);
      if (t != null) {
        final l = jsonDecode(t) as List;
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
    await _blobs.writeText(_sessionsKey, jsonEncode([for (final s in sessions) s.toJson()]));
    await _blobs.writeText(_settingsKey, jsonEncode(settings.toJson()));
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
    final path = 'sheets/$id.jpg';
    await _blobs.writeBytes(path, jpeg);
    _images[path] = Future.value(jpeg);
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
            radius: (s['r'] as num?)?.toDouble(),
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
    await _blobs.delete(sheet.imagePath);
    _images.remove(sheet.imagePath);
    await changed();
  }

  Future<void> deleteSession(Session s) async {
    for (final sh in s.sheets) {
      await _blobs.delete(sh.imagePath);
      _images.remove(sh.imagePath);
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
