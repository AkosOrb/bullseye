"""Teljes kiértékelés: kép -> lövések, pontok, jelzések."""
from __future__ import annotations

from dataclasses import asdict, dataclass, field

import cv2
import numpy as np

from .calibrate import calibrate, valid_mask, warp_canonical
from .detect import anomaly_maps, find_blobs, hole_mask
from .rings import RingModel
from .split import split_blobs
from .target import TargetSpec


@dataclass
class Shot:
    index: int               # 1-based shot number
    x: float                 # original image px
    y: float
    score: int
    radius_px: float         # pellet radius in original px (for drawing)
    dist_mm: float           # centre distance from target centre
    gap_mm: float            # pellet edge to the next higher ring line
    borderline: bool         # "nézőkével ellenőrizendő"
    uncertain: bool          # detection uncertain (split / large blob)
    note: str = ""
    dx_mm: float = 0.0       # offset from centre (right +)
    dy_mm: float = 0.0       # offset from centre (up +)


@dataclass
class Result:
    target: str
    shots: list[Shot]
    total: int
    expected_shots: int | None
    warnings: list[str] = field(default_factory=list)
    calibration: dict = field(default_factory=dict)

    def to_dict(self):
        d = asdict(self)
        return d


def score_point(rm: RingModel, spec: TargetSpec, x: float, y: float):
    """Return (score, gap_px, depth_px) for a hole centred at canonical (x, y).

    gap_px: how far the pellet edge is from touching the next higher ring.
    depth_px: how far the pellet edge reaches past the scored ring's edge
    (small value = it barely touches, the score could be one lower)."""
    sp = rm.spacing
    rp = spec.pellet_radius * sp + spec.edge_tolerance_mm / spec.ring_spacing_mm * sp
    best = 0
    for k in range(spec.ring_count, 0, -1):
        s = rm.signed_dist_to_ring(x, y, k)
        thr = rp if spec.line_touch_counts_higher else 0.0
        if s <= thr:
            best = k
            break
    thr = rp if spec.line_touch_counts_higher else 0.0
    depth = float(thr - rm.signed_dist_to_ring(x, y, best)) if best > 0 else 1e9
    if best == spec.ring_count:
        return best, 0.0, depth
    s_hi = rm.signed_dist_to_ring(x, y, best + 1)
    return best, float(max(0.0, s_hi - thr)), depth


def analyze(img: np.ndarray, spec: TargetSpec, expected: int | None = 15,
            debug: dict | None = None) -> Result:
    valid = valid_mask(img)
    cal = calibrate(img, spec, valid)
    rm = RingModel(cal, spec)
    can, vm = warp_canonical(img, cal, valid)
    g = cv2.cvtColor(can, cv2.COLOR_BGR2GRAY)
    bright, dark, T, PHI, band = anomaly_maps(g, vm, rm, spec)
    m = hole_mask(bright, dark, T, vm, spec, cal.spacing)
    blobs = find_blobs(m, spec, cal.spacing, T, vm, bright, dark, band)
    rp = spec.pellet_radius * cal.spacing
    holes, ns = split_blobs(blobs, rp, expected)

    mm_per_px = spec.ring_spacing_mm / cal.spacing
    cx13, cy13, _ = rm.ring_circle(spec.ring_count)
    shots = []
    for h in holes:
        sc, gap_px, depth_px = score_point(rm, spec, h.x, h.y)
        gap_mm = gap_px * mm_per_px
        depth_mm = depth_px * mm_per_px
        ox, oy = cal.to_orig([[h.x, h.y]])[0]
        dx = (h.x - cx13) * mm_per_px
        dy = -(h.y - cy13) * mm_per_px
        near_hi = sc < spec.ring_count and gap_mm <= spec.borderline_mm
        near_lo = sc > 0 and depth_mm <= spec.borderline_mm / 2
        border = near_hi or near_lo
        note = h.reason
        if near_hi:
            note = (note + "; " if note else "") + f"{gap_mm:.1f} mm-re a {sc + 1}-es gyűrűtől"
        if near_lo:
            note = (note + "; " if note else "") + f"csak {depth_mm:.1f} mm-rel érinti a {sc}-es gyűrűt"
        shots.append(Shot(index=0, x=float(ox), y=float(oy), score=int(sc),
                          radius_px=float(spec.pellet_radius * cal.px_per_spacing_orig),
                          dist_mm=float(np.hypot(dx, dy)), gap_mm=float(gap_mm),
                          borderline=bool(border), uncertain=bool(h.uncertain),
                          note=note, dx_mm=float(dx), dy_mm=float(dy)))
    # number shots top-to-bottom, left-to-right (reading order)
    row = cal.px_per_spacing_orig * 0.8
    shots.sort(key=lambda s: (round(s.y / row), s.x))
    for i, s in enumerate(shots, 1):
        s.index = i
    warnings = []
    if expected is not None and len(shots) != expected:
        if len(shots) < expected:
            warnings.append(f"Csak {len(shots)} lövést találtam a megadott {expected} helyett. "
                            f"Kérlek, pótold a hiányzó {expected - len(shots)} lövést.")
        else:
            warnings.append(f"{len(shots)} lövést találtam a megadott {expected} helyett. "
                            f"Kérlek, töröld a felesleges {len(shots) - expected} lövést.")
    total = sum(s.score for s in shots)
    if debug is not None:
        debug.update(dict(cal=cal, rm=rm, can=can, valid=vm, bright=bright,
                          dark=dark, mask=m, blobs=blobs, holes=holes, T=T))
    calib = dict(ellipse=[list(map(float, cal.ellipse[0])), list(map(float, cal.ellipse[1])),
                          float(cal.ellipse[2])],
                 ring_spacing_px=float(cal.px_per_spacing_orig),
                 rings_found=sorted(int(k) for k in cal.ring_fits))
    return Result(target=spec.id, shots=shots, total=int(total),
                  expected_shots=expected, warnings=warnings, calibration=calib)
