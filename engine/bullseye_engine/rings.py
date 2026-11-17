"""Gyűrűmodell: a mért gyűrűkörökből folytonos "gyűrűkoordináta".

A kiegyenesített képen is maradhat kis perspektív torzulás (a gyűrűk
középpontja sugárral lassan elcsúszik) és nyomdai eltérés (a fekete festék
kissé terül). Ezért nem egyetlen kört használunk, hanem minden mért gyűrűt
külön: a ``t`` névleges sugárhoz (gyűrűtávolság-egységben) lineáris
interpolációval adjuk meg a kör középpontját és sugarát.
"""
from __future__ import annotations

import numpy as np

from .calibrate import Calibration
from .target import TargetSpec


class RingModel:
    def __init__(self, cal: Calibration, spec: TargetSpec):
        self.spec = spec
        ks = sorted(cal.ring_fits)
        n = np.array([spec.ring_radius(k) for k in ks], float)
        cx = np.array([cal.ring_fits[k][0] for k in ks])
        cy = np.array([cal.ring_fits[k][1] for k in ks])
        r = np.array([cal.ring_fits[k][2] for k in ks])
        self.half_width = {k: (cal.ring_fits[k][4] if len(cal.ring_fits[k]) > 4 else 0.0)
                           for k in ks}
        order = np.argsort(n)
        n, cx, cy, r = n[order], cx[order], cy[order], r[order]
        # knot at t=0: centre extrapolated from the innermost rings, R=0
        if len(n) >= 2:
            s = (cx[1] - cx[0]) / (n[1] - n[0]), (cy[1] - cy[0]) / (n[1] - n[0])
        else:
            s = (0.0, 0.0)
        n = np.r_[0.0, n]
        cx = np.r_[cx[0] - s[0] * (n[1]), cx]
        cy = np.r_[cy[0] - s[1] * (n[1]), cy]
        r = np.r_[0.0, r]
        self.n, self.cx, self.cy, self.r = n, cx, cy, r
        self.spacing = cal.spacing

    def _interp(self, t, arr):
        t = np.asarray(t, float)
        n = self.n
        out = np.interp(t, n, arr)
        # linear extrapolation beyond the outermost ring
        hi = t > n[-1]
        if np.any(hi):
            slope = (arr[-1] - arr[-2]) / (n[-1] - n[-2])
            out = np.where(hi, arr[-1] + slope * (t - n[-1]), out)
        return out

    def circle(self, t):
        return self._interp(t, self.cx), self._interp(t, self.cy), self._interp(t, self.r)

    def ring_circle(self, k: int):
        return self.circle(self.spec.ring_radius(k))

    def point(self, t, phi):
        cx, cy, r = self.circle(t)
        return cx + r * np.cos(phi), cy + r * np.sin(phi)

    def coords(self, x, y, iters: int = 6):
        """Inverse map: pixel -> (t, phi)."""
        x = np.asarray(x, float)
        y = np.asarray(y, float)
        t = np.hypot(x - self.cx[1], y - self.cy[1]) / self.spacing
        for _ in range(iters):
            cx, cy, _ = self.circle(t)
            d = np.hypot(x - cx, y - cy)
            # invert R(t) = d  (R is monotone increasing)
            t = self._invert_r(d)
        cx, cy, _ = self.circle(t)
        phi = np.arctan2(y - cy, x - cx)
        return t, phi

    def _invert_r(self, d):
        d = np.asarray(d, float)
        out = np.interp(d, self.r, self.n)
        hi = d > self.r[-1]
        if np.any(hi):
            slope = (self.n[-1] - self.n[-2]) / (self.r[-1] - self.r[-2])
            out = np.where(hi, self.n[-1] + slope * (d - self.r[-1]), out)
        return out

    def local_spacing(self, t):
        t = np.asarray(t, float)
        a = self._interp(np.maximum(t - 0.5, 0), self.r)
        b = self._interp(t + 0.5, self.r)
        return b - a

    def signed_dist_to_ring(self, x, y, k: int):
        """Signed distance to the scoring edge of ring ``k``.

        A printed ring line belongs to the higher ring, so the scoring edge
        is the outer edge of the line (centre + half line width)."""
        cx, cy, r = self.ring_circle(k)
        hw = self.half_width.get(k)
        if hw is None:
            hw = np.median(list(self.half_width.values())) if self.half_width else 0.0
        return np.hypot(x - cx, y - cy) - (r + hw)
