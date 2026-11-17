"""Lőlap-formátum leírása (target spec).

Egy formátumot egy JSON fájl ír le (lásd ``targets/``). A gyűrűk egyenlő
távolságra vannak: a ``k`` pontos gyűrű külső sugara
``(ring_count + 1 - k) * ring_spacing``.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

TARGETS_DIR = Path(__file__).resolve().parent.parent / "targets"


@dataclass
class TargetSpec:
    id: str
    name: str
    ring_count: int
    ring_spacing_mm: float
    pellet_diameter_mm: float
    black_outer_ring: int
    black_inner_ring: int
    label_rings: list[int] = field(default_factory=list)
    label_half_height: float = 0.55
    line_touch_counts_higher: bool = True
    borderline_mm: float = 1.5
    edge_tolerance_mm: float = 0.15

    # --- geometry, in units of the ring spacing -------------------------
    def ring_radius(self, k: int) -> float:
        """Outer radius of ring ``k`` in ring-spacing units."""
        return float(self.ring_count + 1 - k)

    @property
    def black_radius(self) -> float:
        return self.ring_radius(self.black_outer_ring)

    @property
    def white_disk_radius(self) -> float:
        return self.ring_radius(self.black_inner_ring)

    @property
    def pellet_radius(self) -> float:
        """Pellet radius in ring-spacing units (≈0.28 for 4.5 mm / 8 mm)."""
        return self.pellet_diameter_mm / 2.0 / self.ring_spacing_mm

    @property
    def borderline(self) -> float:
        return self.borderline_mm / self.ring_spacing_mm

    def score(self, dist: float) -> tuple[int, float]:
        """Score for a hole whose centre is ``dist`` spacings from the centre.

        Returns ``(score, gap)`` where ``gap`` is how far (in spacing units)
        the pellet edge is from touching the next higher ring (0 for the top
        ring). The highest ring touched by the pellet edge counts.
        """
        edge = dist - self.pellet_radius if self.line_touch_counts_higher else dist
        best = 0
        for k in range(self.ring_count, 0, -1):
            if edge <= self.ring_radius(k):
                best = k
                break
        if best == self.ring_count:
            return best, 0.0
        higher = self.ring_radius(best + 1)
        return best, max(0.0, edge - higher)

    @classmethod
    def load(cls, name_or_path: str) -> "TargetSpec":
        p = Path(name_or_path)
        if not p.exists():
            p = TARGETS_DIR / f"{name_or_path}.json"
        d = json.loads(p.read_text(encoding="utf-8"))
        labels = d.get("labels", {})
        sc = d.get("scoring", {})
        return cls(
            id=d["id"],
            name=d["name"],
            ring_count=d["ring_count"],
            ring_spacing_mm=d["ring_spacing_mm"],
            pellet_diameter_mm=d["pellet_diameter_mm"],
            black_outer_ring=d["black_outer_ring"],
            black_inner_ring=d["black_inner_ring"],
            label_rings=labels.get("rings", []),
            label_half_height=labels.get("half_height_rings", 0.55),
            line_touch_counts_higher=sc.get("line_touch_counts_higher", True),
            borderline_mm=sc.get("borderline_mm", 1.5),
            edge_tolerance_mm=sc.get("edge_tolerance_mm", 0.15),
        )
