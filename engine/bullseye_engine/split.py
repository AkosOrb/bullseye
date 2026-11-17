"""Egymásba lőtt (összefolyó) lyukak szétbontása.

Minden folthoz ``n`` lövést rendelünk. A becslés alapja:

* a folt területe az adott zóna (fekete / fehér) tipikus egylövéses
  területéhez képest,
* k-means lefedés: ``n`` darab, a lövedéknél kicsit nagyobb kör hány
  százalékban fedi le a foltot.

Ha a lövésszám ismert, a hiányzó lövéseket mohó módon azokhoz a
foltokhoz adjuk, ahol a legnagyobb a lefedésbeli nyereség (a folt méretével
súlyozva). Minden szétbontott lövés bizonytalannak számít.
"""
from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np

from .detect import Blob

COVER_R = {"black": 1.3, "white": 1.6}      # coverage radius / pellet radius
SINGLE_AREA = {"black": 0.95, "white": 2.2}  # typical single-hole blob area / pellet area


@dataclass
class Hole:
    x: float
    y: float
    blob_index: int
    n_in_blob: int
    uncertain: bool
    reason: str = ""


def _kmeans(pts: np.ndarray, n: int) -> np.ndarray:
    if n == 1:
        return pts.mean(axis=0, keepdims=True)
    crit = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 60, 0.05)
    cv2.setRNGSeed(1234)
    _, _, cen = cv2.kmeans(pts.astype(np.float32), n, None, crit, 8,
                           cv2.KMEANS_PP_CENTERS)
    return cen.astype(np.float64)


def _coverage(pts, cen, R):
    d = np.min(np.hypot(pts[:, None, 0] - cen[None, :, 0],
                        pts[:, None, 1] - cen[None, :, 1]), axis=1)
    return float((d <= R).mean())


class _BlobModel:
    def __init__(self, blob: Blob, rp: float, a1: float, nmax: int = 8):
        x, y, w, h = blob.bbox
        ys, xs = np.nonzero(blob.mask)
        self.pts = np.c_[xs + x, ys + y].astype(np.float64)
        if len(self.pts) > 4000:
            sel = np.random.default_rng(0).choice(len(self.pts), 4000, replace=False)
            self.pts_s = self.pts[sel]
        else:
            self.pts_s = self.pts
        self.R = COVER_R[blob.zone] * rp
        self.norm_area = blob.area / (SINGLE_AREA[blob.zone] * a1)
        self.nmax = max(1, min(nmax, int(np.ceil(self.norm_area * 1.6)) + 1))
        self._cache = {}

    def centres(self, n):
        if n not in self._cache:
            cen = _kmeans(self.pts_s, n)
            self._cache[n] = (cen, _coverage(self.pts_s, cen, self.R))
        return self._cache[n]

    def gain(self, n):
        """Weighted benefit of going from n to n+1 holes."""
        if n + 1 > self.nmax:
            return -1.0
        c0 = self.centres(n)[1]
        c1 = self.centres(n + 1)[1]
        return (c1 - c0) * self.norm_area

    def natural_n(self, thr=0.9):
        for n in range(1, self.nmax + 1):
            if self.centres(n)[1] >= thr:
                return n
        return self.nmax


def split_blobs(blobs: list[Blob], rp: float, expected: int | None):
    a1 = np.pi * rp * rp
    models = [_BlobModel(b, rp, a1) for b in blobs]
    if expected is None:
        ns = [m.natural_n() for m in models]
    else:
        ns = [1] * len(models)
        while sum(ns) < expected:
            gains = [m.gain(n) for m, n in zip(models, ns)]
            i = int(np.argmax(gains))
            if gains[i] <= 0:
                break
            ns[i] += 1
    holes: list[Hole] = []
    for bi, (m, n) in enumerate(zip(models, ns)):
        cen, cov = m.centres(n)
        agree = m.natural_n() == n
        for c in cen:
            unc = n > 1 and not agree
            reason = "összefolyó lyukakból bontva" if n > 1 else ""
            if n == 1 and m.norm_area > 1.7:
                unc = True
                reason = "nagy folt, lehet több lövés"
            holes.append(Hole(x=float(c[0]), y=float(c[1]), blob_index=bi,
                              n_in_blob=n, uncertain=unc, reason=reason))
    return holes, ns
