"""Találatkeresés a kiegyenesített képen.

Ötlet: a lőlap forgásszimmetrikus, ezért minden sugárhoz (gyűrűkoordináta
szerint) szögszektoronként medián háttérértéket becsülünk. Ami ettől
jelentősen eltér, az találat:

* fekete területen a lyuk világosabb a háttérnél,
* fehér területen a lyuk körüli ólomgyűrű sötétebb a háttérnél.

A gyűrűvonalakat a háttérmodell tartalmazza (sugárirányú min/max tűréssel),
így nem okoznak hamis találatot. A számfeliratok a vízszintes tengelyen
párban szerepelnek (bal és jobb oldalon ugyanaz a szám), ezért a felirat-
sávban a túloldali "ikerpár" a háttér: ami mindkét modellhez képest eltér,
az találat.
"""
from __future__ import annotations

from dataclasses import dataclass, field

import cv2
import numpy as np

from .rings import RingModel
from .target import TargetSpec


@dataclass
class Blob:
    label: int
    area: float
    centroid: tuple
    bbox: tuple
    mask: np.ndarray = field(repr=False)  # bool mask cropped to bbox
    zone: str = "black"
    band_frac: float = 0.0
    strength: float = 0.0


@dataclass
class Detection:
    x: float           # canonical px
    y: float
    blob: int          # index of blob this hole came from
    split_of: int      # number of holes the blob was split into
    confidence: float


def _sector_medians(pol: np.ndarray, sectors: int) -> np.ndarray:
    """Overlapping sector medians interpolated back to full angular res."""
    import warnings
    nt, nphi = pol.shape
    w = nphi // sectors
    ext = np.concatenate([pol[:, -w:], pol, pol[:, :w]], axis=1)
    vals = []
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        for s in range(sectors * 2):
            a = s * w // 2
            vals.append(np.nanmedian(ext[:, a + w // 2: a + w // 2 + w], axis=1))
        glob = np.nanmedian(pol, axis=1)
    vals = np.stack(vals, axis=1)
    bad = np.isnan(vals)
    vals[bad] = np.broadcast_to(glob[:, None], vals.shape)[bad]
    vals = np.nan_to_num(vals, nan=128.0)
    centres = np.arange(sectors * 2) * w / 2.0
    cc = np.r_[centres - nphi, centres, centres + nphi]
    xi = np.arange(nphi)
    full = np.empty((nt, nphi), np.float32)
    for i in range(nt):
        vv = np.r_[vals[i], vals[i], vals[i]]
        full[i] = np.interp(xi, cc, vv)
    return full


def _polar_background(g: np.ndarray, rm: RingModel, t_max: float,
                      dt: float = 1 / 120, nphi: int = 1440):
    """Background per (t, phi): sector medians whose angular width grows
    towards the centre so that one hole never dominates a sector."""
    ts = np.arange(0, t_max, dt)
    phis = np.linspace(-np.pi, np.pi, nphi, endpoint=False)
    T, P = np.meshgrid(ts, phis, indexing="ij")
    X, Y = rm.point(T, P)
    pol = cv2.remap(g, X.astype(np.float32), Y.astype(np.float32),
                    cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT,
                    borderValue=np.nan)
    # arc length of a sector must be >= ~8 hole diameters
    full = np.empty_like(pol)
    choices = [(1, 0.0), (4, 1.6), (8, 3.2), (16, 6.0)]  # (sectors, t_min)
    for sectors, tmin in choices:
        rows = ts >= tmin
        if rows.any():
            full[rows] = _sector_medians(pol[rows], sectors)
    return ts, phis, full


def anomaly_maps(can_gray: np.ndarray, valid: np.ndarray, rm: RingModel,
                 spec: TargetSpec):
    g = can_gray.astype(np.float32)
    size = g.shape[0]
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    T, PHI = rm.coords(xx, yy)
    t_max = float(T[valid].max()) + 0.1 if valid.any() else rm.n[-1] + 2
    ts, phis, B = _polar_background(g, rm, t_max)
    # radial tolerance: lines may be off by ~1-2 px
    tol = 3  # rows of 0.5 px
    k = np.ones((2 * tol + 1, 1), np.uint8)
    Bhi = cv2.dilate(B, k)
    Blo = cv2.erode(B, k)
    ti = (T / (ts[1] - ts[0])).astype(np.float32)
    pi = ((PHI + np.pi) / (2 * np.pi) * len(phis)).astype(np.float32)
    Bhi_c = cv2.remap(Bhi, pi, ti, cv2.INTER_LINEAR, borderMode=cv2.BORDER_WRAP)
    Blo_c = cv2.remap(Blo, pi, ti, cv2.INTER_LINEAR, borderMode=cv2.BORDER_WRAP)
    bright = g - Bhi_c
    dark = Blo_c - g

    # --- label band: compare with the twin label on the other side -------
    band = np.zeros_like(valid)
    if spec.label_rings:
        hh = spec.label_half_height
        # the label axis may be rotated (target not level in the photo):
        # estimate its angle from the label pairs themselves
        theta = _label_axis_angle(g, valid, rm, spec)
        sin = np.sin(PHI - theta)
        cos = np.cos(PHI - theta)
        twin_x = np.full(g.shape, np.nan, np.float32)
        twin_y = np.full(g.shape, np.nan, np.float32)
        cell_id = np.zeros(g.shape, np.int16)
        for ci, kring in enumerate(spec.label_rings):
            tm = spec.ring_radius(kring) - 0.5
            cell = (T > tm - 0.5) & (T <= tm + 0.5) & (np.abs(T * sin) < hh)
            lx, ly = rm.point(tm, theta + np.pi)
            rx, ry = rm.point(tm, theta)
            ox, oy = _refine_twin(g, valid, (lx, ly), (rx, ry), rm.spacing, hh,
                                  search=int(0.2 * rm.spacing))
            rx, ry = lx + ox, ly + oy
            left = cell & (cos < 0)
            right = cell & (cos > 0)
            twin_x[left] = xx[left] + (rx - lx)
            twin_y[left] = yy[left] + (ry - ly)
            twin_x[right] = xx[right] - (rx - lx)
            twin_y[right] = yy[right] - (ry - ly)
            band |= cell
            cell_id[left] = 2 * ci + 1
            cell_id[right] = 2 * ci + 2
        gmax = cv2.dilate(g, np.ones((7, 7), np.uint8))
        gmin = cv2.erode(g, np.ones((7, 7), np.uint8))
        tx = np.nan_to_num(twin_x, nan=-10).astype(np.float32)
        ty = np.nan_to_num(twin_y, nan=-10).astype(np.float32)
        twin_hi = cv2.remap(gmax, tx, ty, cv2.INTER_LINEAR,
                            borderMode=cv2.BORDER_CONSTANT, borderValue=255)
        twin_lo = cv2.remap(gmin, tx, ty, cv2.INTER_LINEAR,
                            borderMode=cv2.BORDER_CONSTANT, borderValue=0)
        vtw = cv2.remap(valid.astype(np.uint8), tx, ty, cv2.INTER_NEAREST,
                        borderMode=cv2.BORDER_CONSTANT, borderValue=0) > 0
        twin = cv2.remap(g, tx, ty, cv2.INTER_LINEAR,
                         borderMode=cv2.BORDER_CONSTANT, borderValue=0)
        use = band & vtw
        # photometric correction per cell (lighting differs left/right)
        for cid in np.unique(cell_id[use]):
            sel = use & (cell_id == cid)
            a, b = _robust_linfit(twin[sel], g[sel])
            twin_hi[sel] = a * twin_hi[sel] + b
            twin_lo[sel] = a * twin_lo[sel] + b
        b2 = g - twin_hi
        d2 = twin_lo - g
        bright = np.where(use, np.minimum(bright, b2), bright)
        dark = np.where(use, np.minimum(dark, d2), dark)
        # label cells whose twin is not visible cannot be told apart from
        # holes reliably: suppress them (the shot-count check will ask the
        # user to add a missing shot if one was there)
        nouse = band & ~vtw
        # a cell whose twin is only partly visible is unreliable as a whole
        for cid in np.unique(cell_id[band]):
            if cid == 0:
                continue
            sel = band & (cell_id == cid)
            if vtw[sel].mean() < 0.97:
                nouse |= sel
        bright = np.where(nouse, 0, bright)
        dark = np.where(nouse, 0, dark)
    bright[~valid] = 0
    dark[~valid] = 0
    return bright, dark, T, PHI, band


def _label_axis_angle(g, valid, rm, spec, max_deg=8.0):
    """Angle of the label axis, from template matching the label pairs."""
    angs = []
    hh = spec.label_half_height
    for kring in spec.label_rings:
        tm = spec.ring_radius(kring) - 0.5
        lc = rm.point(tm, np.pi)
        rc = rm.point(tm, 0.0)
        search = int(np.tan(np.deg2rad(max_deg)) * tm * rm.spacing) + 4
        ox, oy = _refine_twin(g, valid, lc, rc, rm.spacing, hh, search=search,
                              min_corr=0.6)
        base = (rc[0] - lc[0], rc[1] - lc[1])
        if (ox, oy) == base:
            continue
        angs.append(np.arctan2(oy, ox))
    if not angs:
        return 0.0
    return float(np.median(angs))


def _robust_linfit(x, y, iters=3):
    keep = np.ones(len(x), bool)
    a, b = 1.0, 0.0
    for _ in range(iters):
        if keep.sum() < 20 or np.std(x[keep]) < 1:
            break
        a, b = np.polyfit(x[keep], y[keep], 1)
        res = np.abs(y - (a * x + b))
        keep = res < max(15.0, 2.5 * np.median(res[keep]))
    a = float(np.clip(a, 0.7, 1.4))
    return a, float(b)


def _refine_twin(g, valid, lc, rc, spacing, hh, search=None, min_corr=0.5):
    if search is None:
        search = int(0.5 * spacing)
    half_w = int(0.42 * spacing)
    half_h = int(hh * spacing * 0.9)
    lx, ly = int(round(lc[0])), int(round(lc[1]))
    rx, ry = int(round(rc[0])), int(round(rc[1]))
    H, W = g.shape
    def ok(x0, y0, x1, y1):
        return x0 >= 0 and y0 >= 0 and x1 <= W and y1 <= H and valid[y0:y1, x0:x1].all()
    base = (rc[0] - lc[0], rc[1] - lc[1])
    if not (ok(lx - half_w, ly - half_h, lx + half_w, ly + half_h) and
            ok(rx - half_w - search, ry - half_h - search,
               rx + half_w + search, ry + half_h + search)):
        return base
    tpl = g[ly - half_h:ly + half_h, lx - half_w:lx + half_w]
    reg = g[ry - half_h - search:ry + half_h + search,
            rx - half_w - search:rx + half_w + search]
    if tpl.std() < 5:
        return base
    res = cv2.matchTemplate(reg, tpl, cv2.TM_CCOEFF_NORMED)
    _, mx, _, loc = cv2.minMaxLoc(res)
    if mx < min_corr:
        return base
    dx = loc[0] - search
    dy = loc[1] - search
    # sub-pixel
    def sub(a, b, c):
        den = a - 2 * b + c
        return 0.5 * (a - c) / den if abs(den) > 1e-6 else 0.0
    i, j = loc[1], loc[0]
    fx = sub(res[i, j - 1], res[i, j], res[i, j + 1]) if 0 < j < res.shape[1] - 1 else 0
    fy = sub(res[i - 1, j], res[i, j], res[i + 1, j]) if 0 < i < res.shape[0] - 1 else 0
    return (rx - lx + dx + fx, ry - ly + dy + fy)


def hole_mask(bright, dark, T, valid, spec: TargetSpec, spacing: float,
              tb: float = 45.0, tw: float = 20.0):
    """Binary hole mask from the anomaly maps.

    Black area: bright pixels (paper hole). White area: blurred darkness
    (lead ring + grey hole interior)."""
    rp = spec.pellet_radius * spacing
    mb = (bright > tb) & valid
    dsm = cv2.GaussianBlur(np.maximum(dark, 0).astype(np.float32), (0, 0), rp * 0.4)
    mw = (dsm > tw) & valid
    m = (mb | mw).astype(np.uint8) * 255
    kc = max(3, int(rp * 0.5)) | 1
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE,
                         cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kc, kc)))
    m = _fill_holes(m)
    ko = max(3, int(rp * 0.6)) | 1
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN,
                         cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (ko, ko)))
    return m > 0


def _fill_holes(m):
    h, w = m.shape
    ff = m.copy()
    mask = np.zeros((h + 2, w + 2), np.uint8)
    cv2.floodFill(ff, mask, (0, 0), 255)
    return m | cv2.bitwise_not(ff)


def find_blobs(mask: np.ndarray, spec: TargetSpec, spacing: float, T,
               valid: np.ndarray, bright: np.ndarray, dark: np.ndarray,
               band: np.ndarray | None = None,
               tb: float = 45.0, tw: float = 28.0):
    rp = spec.pellet_radius * spacing
    a1 = np.pi * rp * rp
    border = cv2.dilate((~valid).astype(np.uint8),
                        cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (int(rp), int(rp)) )) > 0
    strong = (bright > tb) | (dark > tw)
    n, lab, st, cen = cv2.connectedComponentsWithStats(mask.astype(np.uint8))
    blobs = []
    for i in range(1, n):
        area = st[i, cv2.CC_STAT_AREA]
        if area < 0.25 * a1:
            continue
        x, y, w, h = st[i, :4]
        sub = lab[y:y + h, x:x + w] == i
        if border[y:y + h, x:x + w][sub].any():
            continue
        if strong[y:y + h, x:x + w][sub].sum() < 0.2 * a1:
            continue
        cx, cy = cen[i]
        t = T[int(cy), int(cx)]
        zone = "black" if spec.white_disk_radius <= t <= spec.black_radius else "white"
        bb = bright[y:y + h, x:x + w][sub]
        dd = dark[y:y + h, x:x + w][sub]
        strength = float(np.median(bb)) if zone == "black" else float(np.percentile(dd, 90))
        bf = float(band[y:y + h, x:x + w][sub].mean()) if band is not None else 0.0
        # weak blobs that sit on a number label are label residue
        if bf > 0.5 and zone == "black" and strength < 70:
            continue
        blobs.append(Blob(label=i, area=float(area), centroid=(cx, cy),
                          bbox=(x, y, w, h), mask=sub, zone=zone,
                          band_frac=bf, strength=strength))
    return blobs
