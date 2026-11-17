"""Kalibrálás: a fekete korong ellipszise + a gyűrűvonalak körillesztése.

1. A fekete korong szélére robusztus (RANSAC) ellipszist illesztünk. Ebből
   egy affin transzformációval "kiegyenesített" (canonical) képet készítünk,
   amelyen a gyűrűk körök, és a gyűrűtávolság ``D`` pixel.
2. A kiegyenesített képen sugárirányú profilokkal megkeressük az egyes
   gyűrűvonalakat (fekete korong széle, fehér vonalak a feketében, fehér
   korong széle, fekete vonalak a fehérben), és robusztus körillesztéssel
   finomítjuk a középpontot és a gyűrűtávolságot.
"""
from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np

from .target import TargetSpec

D = 60.0  # ring spacing in canonical pixels


@dataclass
class Calibration:
    A: np.ndarray          # 2x3 affine: original -> canonical
    Ainv: np.ndarray       # 2x3 affine: canonical -> original
    size: int              # canonical image is size x size
    center: np.ndarray     # refined centre in canonical px
    spacing: float         # refined ring spacing in canonical px
    ellipse: tuple         # black-disk ellipse in original image
    ring_fits: dict        # ring number -> (cx, cy, r, n_points)
    px_per_spacing_orig: float  # approx ring spacing in original px

    def to_canon(self, pts: np.ndarray) -> np.ndarray:
        pts = np.asarray(pts, dtype=np.float64).reshape(-1, 2)
        return pts @ self.A[:, :2].T + self.A[:, 2]

    def to_orig(self, pts: np.ndarray) -> np.ndarray:
        pts = np.asarray(pts, dtype=np.float64).reshape(-1, 2)
        return pts @ self.Ainv[:, :2].T + self.Ainv[:, 2]


class CalibrationError(RuntimeError):
    pass


def valid_mask(img: np.ndarray) -> np.ndarray:
    """Pixels that belong to the photo (not flat pure-white padding)."""
    pad = (img >= 254).all(axis=2).astype(np.uint8)
    # only large connected flat regions count as padding
    n, lab, st, _ = cv2.connectedComponentsWithStats(pad)
    mask = np.ones(pad.shape, bool)
    min_area = 0.02 * pad.size
    for i in range(1, n):
        if st[i, cv2.CC_STAT_AREA] > min_area:
            mask[lab == i] = False
    return mask


def _fit_ellipse_ransac(pts: np.ndarray, iters: int = 400, tol: float = 3.0,
                        rng: np.random.Generator | None = None):
    rng = rng or np.random.default_rng(0)
    best_inl = None
    n = len(pts)
    if n < 20:
        raise CalibrationError("Túl kevés pont az ellipszishez.")
    for _ in range(iters):
        idx = rng.choice(n, 6, replace=False)
        try:
            e = cv2.fitEllipse(pts[idx].astype(np.float32))
        except cv2.error:
            continue
        (cx, cy), (w, h), ang = e
        if min(w, h) < 50 or max(w, h) / max(min(w, h), 1) > 1.6:
            continue
        r = _ellipse_residual(pts, e)
        inl = r < tol
        if best_inl is None or inl.sum() > best_inl.sum():
            best_inl = inl
    if best_inl is None:
        raise CalibrationError("Nem sikerült ellipszist illeszteni.")
    e = cv2.fitEllipse(pts[best_inl].astype(np.float32))
    for _ in range(3):
        inl = _ellipse_residual(pts, e) < tol
        e = cv2.fitEllipse(pts[inl].astype(np.float32))
    return e, inl


def _ellipse_residual(pts, e):
    (cx, cy), (w, h), ang = e
    t = np.deg2rad(ang)
    c, s = np.cos(t), np.sin(t)
    x = pts[:, 0] - cx
    y = pts[:, 1] - cy
    u = x * c + y * s
    v = -x * s + y * c
    a, b = w / 2.0, h / 2.0
    rr = np.sqrt((u / a) ** 2 + (v / b) ** 2)
    return np.abs(rr - 1.0) * (a + b) / 2.0


def find_black_disk(img: np.ndarray, valid: np.ndarray):
    g = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    b = cv2.GaussianBlur(g, (0, 0), 3)
    t, _ = cv2.threshold(b[valid].reshape(-1, 1), 0, 255,
                         cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    dark = ((b < t) & valid).astype(np.uint8) * 255
    k = max(15, int(min(img.shape[:2]) * 0.03)) | 1
    dark = cv2.morphologyEx(dark, cv2.MORPH_CLOSE,
                            cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k)))
    n, lab, st, _ = cv2.connectedComponentsWithStats(dark)
    if n < 2:
        raise CalibrationError("Nem található a fekete korong.")
    i = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    comp = (lab == i).astype(np.uint8) * 255
    cs, _ = cv2.findContours(comp, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    c = max(cs, key=cv2.contourArea)[:, 0, :].astype(np.float64)
    # drop contour points on the photo border (disk may be clipped)
    inv = (~valid).astype(np.uint8)
    inv = cv2.dilate(inv, np.ones((9, 9), np.uint8))
    h, w = valid.shape
    xi = c[:, 0].astype(int)
    yi = c[:, 1].astype(int)
    keep = (xi > 4) & (yi > 4) & (xi < w - 5) & (yi < h - 5) & (inv[yi, xi] == 0)
    c = c[keep]
    e, _ = _fit_ellipse_ransac(c)
    return e


def _affine_from_ellipse(e, R0: float, C: float):
    (cx, cy), (w, h), ang = e
    t = np.deg2rad(ang)
    Rot = np.array([[np.cos(t), -np.sin(t)], [np.sin(t), np.cos(t)]])
    S = np.diag([R0 / (w / 2.0), R0 / (h / 2.0)])
    M = Rot @ S @ Rot.T
    A = np.zeros((2, 3))
    A[:, :2] = M
    A[:, 2] = np.array([C, C]) - M @ np.array([cx, cy])
    return A


def _invert_affine(A):
    M = A[:, :2]
    Mi = np.linalg.inv(M)
    Ai = np.zeros((2, 3))
    Ai[:, :2] = Mi
    Ai[:, 2] = -Mi @ A[:, 2]
    return Ai


def _line_half_width(canf, fit, inside_black, lab_ok):
    """Half of the printed line width (FWHM), in canonical px."""
    cx, cy, r = fit[:3]
    rs = np.arange(r - 8, r + 8, 0.25)
    ph = np.linspace(0, 2 * np.pi, 360, endpoint=False)
    ph = ph[np.abs(np.sin(ph)) > 0.3]
    X = cx + np.outer(np.cos(ph), rs)
    Y = cy + np.outer(np.sin(ph), rs)
    P = cv2.remap(canf, X.astype(np.float32), Y.astype(np.float32), cv2.INTER_LINEAR)
    prof = np.median(P, axis=0)
    if not inside_black:
        prof = -prof
    base = np.median(np.r_[prof[:8], prof[-8:]])
    half = (base + prof.max()) / 2
    w = float((prof > half).sum()) * 0.25
    return float(np.clip(w / 2, 0.0, 4.0))


def _fit_circle(pts):
    x, y = pts[:, 0], pts[:, 1]
    A = np.c_[2 * x, 2 * y, np.ones_like(x)]
    b = x ** 2 + y ** 2
    sol, *_ = np.linalg.lstsq(A, b, rcond=None)
    cx, cy, c = sol
    r = np.sqrt(max(c + cx ** 2 + cy ** 2, 1e-9))
    return cx, cy, r


def _robust_circle(pts, iters=4):
    keep = np.ones(len(pts), bool)
    cx = cy = r = None
    for _ in range(iters):
        if keep.sum() < 12:
            return None
        cx, cy, r = _fit_circle(pts[keep])
        res = np.abs(np.hypot(pts[:, 0] - cx, pts[:, 1] - cy) - r)
        mad = np.median(res[keep]) * 1.4826 + 0.3
        keep = res < max(2.5 * mad, 0.8)
    return cx, cy, r, int(keep.sum())


def calibrate(img: np.ndarray, spec: TargetSpec, valid: np.ndarray | None = None
              ) -> Calibration:
    if valid is None:
        valid = valid_mask(img)
    e = find_black_disk(img, valid)
    R_black = spec.black_radius * D
    half = int(np.ceil((spec.black_radius + 2.5) * D))
    size = 2 * half
    A = _affine_from_ellipse(e, R_black, half)
    g = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    can = cv2.warpAffine(g, A, (size, size), flags=cv2.INTER_LINEAR,
                         borderValue=0)
    vmask = cv2.warpAffine(valid.astype(np.uint8), A, (size, size),
                           flags=cv2.INTER_NEAREST, borderValue=0) > 0
    vmask = cv2.erode(vmask.astype(np.uint8), np.ones((7, 7), np.uint8)) > 0
    canf = cv2.GaussianBlur(can.astype(np.float32), (0, 0), 1.0)

    # --- ring line refinement --------------------------------------------
    nang = 720
    angs = np.linspace(0, 2 * np.pi, nang, endpoint=False)
    # avoid the label band on the horizontal axis
    lab_ok = np.abs(np.sin(angs)) > 0.16
    ring_fits = {}
    win = 0.28 * D
    for k in range(1, spec.ring_count + 1):
        r0 = spec.ring_radius(k) * D
        if r0 + win >= half - 2:
            continue
        rs = np.arange(r0 - win, r0 + win, 0.5)
        X = half + np.outer(np.cos(angs), rs)
        Y = half + np.outer(np.sin(angs), rs)
        prof = cv2.remap(canf, X.astype(np.float32), Y.astype(np.float32),
                         cv2.INTER_LINEAR)
        okm = cv2.remap(vmask.astype(np.uint8), X.astype(np.float32),
                        Y.astype(np.float32), cv2.INTER_NEAREST).all(axis=1)
        if k == spec.black_outer_ring or k == spec.black_inner_ring:
            # step edge: black inside (k==black_outer) or outside (inner)
            d = np.diff(prof, axis=1)
            if k == spec.black_inner_ring:
                d = -d
            idx = np.argmax(d, axis=1)
            strength = d[np.arange(nang), idx]
            pos = rs[idx] + 0.25
            good = strength > 6
        else:
            inside_black = spec.black_outer_ring < k < spec.black_inner_ring
            p = prof if inside_black else -prof
            idx = np.argmax(p, axis=1)
            idx = np.clip(idx, 1, len(rs) - 2)
            rowi = np.arange(nang)
            y0, y1, y2 = p[rowi, idx - 1], p[rowi, idx], p[rowi, idx + 1]
            den = (y0 - 2 * y1 + y2)
            with np.errstate(all="ignore"):
                off = np.where(np.abs(den) > 1e-6, 0.5 * (y0 - y2) / den, 0.0)
            pos = rs[idx] + np.clip(off, -1, 1) * 0.5
            base = np.median(p, axis=1)
            strength = y1 - base
            good = strength > 12
        good &= okm & lab_ok
        if good.sum() < 40:
            continue
        pts = np.c_[half + np.cos(angs[good]) * pos[good],
                    half + np.sin(angs[good]) * pos[good]]
        fit = _robust_circle(pts)
        if fit is not None and fit[3] > 40:
            hw = 0.0
            if not (k == spec.black_outer_ring or k == spec.black_inner_ring):
                hw = _line_half_width(canf, fit, inside_black, lab_ok)
            ring_fits[k] = (*fit, hw)
    if len(ring_fits) < 3:
        raise CalibrationError("Kevés gyűrűvonal található, a fotó nem megfelelő.")

    # joint model: common centre, radius = n_k * spacing
    ks = np.array(sorted(ring_fits))
    n = np.array([spec.ring_radius(k) for k in ks])
    rs = np.array([ring_fits[k][2] for k in ks])
    w = np.array([ring_fits[k][3] for k in ks], float)
    spacing = float(np.sum(w * n * rs) / np.sum(w * n * n))
    cxy = np.array([[ring_fits[k][0], ring_fits[k][1]] for k in ks])
    # inner rings carry the centre most precisely; weight by point count
    center = (cxy * w[:, None]).sum(0) / w.sum()

    Ainv = _invert_affine(A)
    px_orig = spacing / np.sqrt(abs(np.linalg.det(A[:, :2])))
    return Calibration(A=A, Ainv=Ainv, size=size, center=center,
                       spacing=spacing, ellipse=e, ring_fits=ring_fits,
                       px_per_spacing_orig=float(px_orig))


def warp_canonical(img: np.ndarray, cal: Calibration, valid: np.ndarray):
    can = cv2.warpAffine(img, cal.A, (cal.size, cal.size),
                         flags=cv2.INTER_LINEAR, borderValue=(0, 0, 0))
    vm = cv2.warpAffine(valid.astype(np.uint8), cal.A, (cal.size, cal.size),
                        flags=cv2.INTER_NEAREST, borderValue=0) > 0
    vm = cv2.erode(vm.astype(np.uint8), np.ones((9, 9), np.uint8)) > 0
    return can, vm
