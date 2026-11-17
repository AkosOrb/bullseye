// Lőlap-formátum leírása. Az alapértelmezett az MDLSz gyorspont lőlap; új
// formátum egy újabb [TargetSpec] (vagy JSON) hozzáadásával bővíthető.
//
// A gyűrűk egyenlő távolságra vannak: a k pontos gyűrű külső sugara
// (ringCount + 1 - k) * ringSpacing.

class TargetSpec {
  final String id;
  final String name;
  final int ringCount;
  final double ringSpacingMm;
  final double pelletDiameterMm;
  final int blackOuterRing;
  final int blackInnerRing;
  final List<int> labelRings;
  final double labelHalfHeight;
  final bool lineTouchCountsHigher;
  final double borderlineMm;
  final double edgeToleranceMm;

  const TargetSpec({
    required this.id,
    required this.name,
    required this.ringCount,
    required this.ringSpacingMm,
    required this.pelletDiameterMm,
    required this.blackOuterRing,
    required this.blackInnerRing,
    this.labelRings = const [],
    this.labelHalfHeight = 0.6,
    this.lineTouchCountsHigher = true,
    this.borderlineMm = 1.5,
    this.edgeToleranceMm = 0.15,
  });

  static const mdlszGyorspont = TargetSpec(
    id: 'mdlsz_gyorspont',
    name: 'MDLSz gyorspont lőlap',
    ringCount: 13,
    ringSpacingMm: 8.0,
    pelletDiameterMm: 4.5,
    blackOuterRing: 6,
    blackInnerRing: 11,
    labelRings: [5, 6, 7, 8, 9, 10, 11, 12],
  );

  static const all = [mdlszGyorspont];

  static TargetSpec byId(String id) =>
      all.firstWhere((t) => t.id == id, orElse: () => mdlszGyorspont);

  TargetSpec copyWith({bool? lineTouchCountsHigher, double? borderlineMm}) => TargetSpec(
        id: id,
        name: name,
        ringCount: ringCount,
        ringSpacingMm: ringSpacingMm,
        pelletDiameterMm: pelletDiameterMm,
        blackOuterRing: blackOuterRing,
        blackInnerRing: blackInnerRing,
        labelRings: labelRings,
        labelHalfHeight: labelHalfHeight,
        lineTouchCountsHigher: lineTouchCountsHigher ?? this.lineTouchCountsHigher,
        borderlineMm: borderlineMm ?? this.borderlineMm,
        edgeToleranceMm: edgeToleranceMm,
      );

  /// A k pontos gyűrű külső sugara gyűrűtávolság-egységben.
  double ringRadius(int k) => (ringCount + 1 - k).toDouble();
  double get blackRadius => ringRadius(blackOuterRing);
  double get whiteDiskRadius => ringRadius(blackInnerRing);

  /// Lövedéksugár gyűrűtávolság-egységben (≈0,28).
  double get pelletRadius => pelletDiameterMm / 2 / ringSpacingMm;

  /// Ideális geometriai pontozás (tesztekhez, kézi lövéshez kalibráció nélkül).
  int scoreForDistance(double distSpacings) {
    final edge = lineTouchCountsHigher ? distSpacings - pelletRadius : distSpacings;
    for (var k = ringCount; k >= 1; k--) {
      if (edge <= ringRadius(k)) return k;
    }
    return 0;
  }
}
