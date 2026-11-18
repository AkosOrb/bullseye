// Adatmodell: edzés (Session) -> lapok (Sheet) -> lövések (Shot).
import '../engine/pipeline.dart';
import '../engine/target.dart';

class Shot {
  String id;
  double x, y; // a lap fotóján (feldolgozott kép koordinátái)
  int? override; // kézzel felülírt pontszám
  bool auto; // a felismerő találta (nem kézi hozzáadás)
  bool uncertain; // felismerési bizonytalanság (pl. szétbontott lyuk)
  String detectNote;
  /// A találati kör sugara a fotón (px), a koromgyűrűből mérve vagy kézzel
  /// igazítva; null = a névleges 4,5 mm-es lövedékméret.
  double? radius;

  Shot({
    required this.id,
    required this.x,
    required this.y,
    this.override,
    this.auto = true,
    this.uncertain = false,
    this.detectNote = '',
    this.radius,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        if (override != null) 'override': override,
        'auto': auto,
        'uncertain': uncertain,
        'note': detectNote,
        if (radius != null) 'r': radius,
      };

  static Shot fromJson(Map<String, dynamic> j) => Shot(
        id: j['id'] as String,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        override: j['override'] as int?,
        auto: j['auto'] as bool? ?? true,
        uncertain: j['uncertain'] as bool? ?? false,
        detectNote: j['note'] as String? ?? '',
        radius: (j['r'] as num?)?.toDouble(),
      );
}

/// Egy lövés kiszámolt adatai (a geometriából, a felülírással együtt).
class ShotView {
  final Shot shot;
  final int index; // 1-től
  final ShotScore? computed;
  const ShotView(this.shot, this.index, this.computed);

  int get score => shot.override ?? computed?.score ?? 0;
  bool get overridden => shot.override != null;

  /// Nézőkével ellenőrizendő: bizonytalan felismerés vagy határeset.
  bool get needsCheck => !overridden && (shot.uncertain || (computed?.borderline ?? false));

  String get note {
    final parts = <String>[
      if (shot.detectNote.isNotEmpty && shot.uncertain) shot.detectNote,
      if (computed != null && computed!.note.isNotEmpty) computed!.note,
    ];
    return parts.join('; ');
  }
}

class Sheet {
  String id;
  DateTime createdAt;
  String imagePath; // a feldolgozott (kicsinyített, elforgatott) kép
  int imageW, imageH;
  int expectedShots;
  TargetGeometry? geometry;
  String targetId;
  List<Shot> shots;
  /// A lap neve (pl. „1. sorozat”) és a lövő neve versenyhez; üres = nincs megadva.
  String name;
  String shooter;

  Sheet({
    required this.id,
    required this.createdAt,
    required this.imagePath,
    required this.imageW,
    required this.imageH,
    required this.expectedShots,
    required this.geometry,
    required this.targetId,
    required this.shots,
    this.name = '',
    this.shooter = '',
  });

  TargetSpec get spec => geometry?.spec ?? TargetSpec.byId(targetId);

  /// Lövések sorszámmal és pontszámmal (a sorrend: a lista sorrendje).
  List<ShotView> views() {
    final g = geometry;
    return [
      for (var i = 0; i < shots.length; i++)
        ShotView(shots[i], i + 1, g?.scoreOrig(shots[i].x, shots[i].y, radiusOrig: shots[i].radius)),
    ];
  }

  int get total => views().fold(0, (a, v) => a + v.score);

  /// Szabályos lövésszám a lap típusához (gyorspont: 15).
  int get regulationShots => spec.regulationShots;

  /// Több lövés van a lapon, mint a szabályos – értékeljük, csak jelezzük.
  bool get irregular => shots.length > regulationShots;

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'imagePath': imagePath,
        'imageW': imageW,
        'imageH': imageH,
        'expectedShots': expectedShots,
        'targetId': targetId,
        if (geometry != null) 'geometry': geometry!.toJson(),
        'shots': [for (final s in shots) s.toJson()],
        if (name.isNotEmpty) 'name': name,
        if (shooter.isNotEmpty) 'shooter': shooter,
      };

  static Sheet fromJson(Map<String, dynamic> j, {TargetSpec Function(String id)? specFor}) {
    final targetId = j['targetId'] as String? ?? TargetSpec.mdlszGyorspont.id;
    final spec = specFor?.call(targetId) ?? TargetSpec.byId(targetId);
    return Sheet(
      id: j['id'] as String,
      createdAt: DateTime.parse(j['createdAt'] as String),
      imagePath: j['imagePath'] as String,
      imageW: j['imageW'] as int,
      imageH: j['imageH'] as int,
      expectedShots: j['expectedShots'] as int? ?? 15,
      targetId: targetId,
      name: j['name'] as String? ?? '',
      shooter: j['shooter'] as String? ?? '',
      geometry: j['geometry'] == null
          ? null
          : TargetGeometry.fromJson((j['geometry'] as Map).cast<String, dynamic>(), spec: spec),
      shots: [for (final s in (j['shots'] as List)) Shot.fromJson((s as Map).cast<String, dynamic>())],
    );
  }
}

class Session {
  String id;
  DateTime date;
  String title;
  List<Sheet> sheets;

  Session({required this.id, required this.date, this.title = '', List<Sheet>? sheets})
      : sheets = sheets ?? [];

  int get total => sheets.fold(0, (a, s) => a + s.total);
  int get shotCount => sheets.fold(0, (a, s) => a + s.shots.length);
  double get averagePerSheet => sheets.isEmpty ? 0 : total / sheets.length;
  double get averagePerShot => shotCount == 0 ? 0 : total / shotCount;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'title': title,
        'sheets': [for (final s in sheets) s.toJson()],
      };

  static Session fromJson(Map<String, dynamic> j, {TargetSpec Function(String id)? specFor}) => Session(
        id: j['id'] as String,
        date: DateTime.parse(j['date'] as String),
        title: j['title'] as String? ?? '',
        sheets: [
          for (final s in (j['sheets'] as List))
            Sheet.fromJson((s as Map).cast<String, dynamic>(), specFor: specFor)
        ],
      );
}

class AppSettings {
  int defaultShots;
  String targetId;
  bool lineTouchCountsHigher;
  double borderlineMm;

  AppSettings({
    this.defaultShots = 15,
    this.targetId = 'mdlsz_gyorspont',
    this.lineTouchCountsHigher = true,
    this.borderlineMm = 1.5,
  });

  TargetSpec specFor(String id) => TargetSpec.byId(id)
      .copyWith(lineTouchCountsHigher: lineTouchCountsHigher, borderlineMm: borderlineMm);

  TargetSpec get spec => specFor(targetId);

  Map<String, dynamic> toJson() => {
        'defaultShots': defaultShots,
        'targetId': targetId,
        'lineTouchCountsHigher': lineTouchCountsHigher,
        'borderlineMm': borderlineMm,
      };

  static AppSettings fromJson(Map<String, dynamic> j) => AppSettings(
        defaultShots: j['defaultShots'] as int? ?? 15,
        targetId: j['targetId'] as String? ?? 'mdlsz_gyorspont',
        lineTouchCountsHigher: j['lineTouchCountsHigher'] as bool? ?? true,
        borderlineMm: (j['borderlineMm'] as num?)?.toDouble() ?? 1.5,
      );
}
