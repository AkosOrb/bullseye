"""Jelölt kép készítése: színes kör + sorszám és pont minden találatnál.

A címkéket úgy helyezzük el, hogy ne takarják egymást és a köröket.
"""
from __future__ import annotations

import cv2
import numpy as np

from .pipeline import Result

# BGR colours by score band
def score_colour(score: int) -> tuple:
    if score >= 13:
        return (40, 200, 255)    # gold
    if score >= 11:
        return (60, 200, 60)     # green
    if score >= 9:
        return (230, 160, 30)    # blue
    if score >= 7:
        return (200, 80, 200)    # purple
    return (60, 60, 230)         # red


def _rects_overlap(a, b, pad=2):
    return not (a[2] + pad <= b[0] or b[2] + pad <= a[0] or a[3] + pad <= b[1] or b[3] + pad <= a[1])


def _circle_rect_overlap(c, r, rect):
    x = min(max(c[0], rect[0]), rect[2])
    y = min(max(c[1], rect[1]), rect[3])
    return (x - c[0]) ** 2 + (y - c[1]) ** 2 < r * r


def annotate(img: np.ndarray, res: Result, crop: bool = True) -> np.ndarray:
    out = img.copy()
    h, w = out.shape[:2]
    scale = max(0.45, min(w, h) / 1600.0)
    font = cv2.FONT_HERSHEY_SIMPLEX
    th = max(1, int(round(scale * 2)))
    circles = [((s.x, s.y), s.radius_px * 1.15) for s in res.shots]
    placed = []
    for s in res.shots:
        col = score_colour(s.score)
        c = (int(round(s.x)), int(round(s.y)))
        r = int(round(s.radius_px * 1.15))
        cv2.circle(out, c, r, (255, 255, 255), th + 3, cv2.LINE_AA)
        cv2.circle(out, c, r, col, th + 1, cv2.LINE_AA)
        if s.borderline or s.uncertain:
            cv2.circle(out, c, r + 3 * th + 2, (0, 165, 255), th, cv2.LINE_AA)
    for s in res.shots:
        col = score_colour(s.score)
        text = f"{s.index}: {s.score}" + ("?" if (s.borderline or s.uncertain) else "")
        (tw, tht), base = cv2.getTextSize(text, font, scale, th)
        r = s.radius_px * 1.15 + 4
        best = None
        for dist in (r, r + 10, r + 22, r + 36, r + 54):
            for ang in np.deg2rad([0, 180, -45, 45, -135, 135, -90, 90, 20, 160, -20, -160]):
                ax = s.x + np.cos(ang) * dist
                ay = s.y + np.sin(ang) * dist
                x0 = ax if np.cos(ang) >= -0.01 else ax - tw
                if abs(np.cos(ang)) < 0.3:
                    x0 = ax - tw / 2
                y0 = ay - tht / 2 if abs(np.sin(ang)) < 0.5 else (ay - tht if np.sin(ang) < 0 else ay)
                rect = (x0 - 3, y0 - 3, x0 + tw + 3, y0 + tht + base + 3)
                if rect[0] < 0 or rect[1] < 0 or rect[2] > w or rect[3] > h:
                    continue
                if any(_rects_overlap(rect, p) for p in placed):
                    continue
                if any(_circle_rect_overlap(cc, cr, rect) for cc, cr in circles):
                    continue
                best = (rect, (x0, y0))
                break
            if best:
                break
        if best is None:
            x0, y0 = s.x + r, s.y - tht / 2
            best = ((x0 - 3, y0 - 3, x0 + tw + 3, y0 + tht + base + 3), (x0, y0))
        rect, (x0, y0) = best
        placed.append(rect)
        # leader line when the label is detached
        rc = ((rect[0] + rect[2]) / 2, (rect[1] + rect[3]) / 2)
        cv2.rectangle(out, (int(rect[0]), int(rect[1])), (int(rect[2]), int(rect[3])),
                      (255, 255, 255), -1)
        cv2.rectangle(out, (int(rect[0]), int(rect[1])), (int(rect[2]), int(rect[3])), col, th)
        cv2.putText(out, text, (int(x0), int(y0 + tht)), font, scale, (20, 20, 20), th, cv2.LINE_AA)
    # header
    hdr = f"{len(res.shots)} lovés - osszesen: {res.total} pont"
    hdr = f"{len(res.shots)} loves  |  osszesen: {res.total} pont"
    (tw, tht), base = cv2.getTextSize(hdr, font, scale * 1.3, th + 1)
    cv2.rectangle(out, (10, 10), (30 + tw, 30 + tht + base), (255, 255, 255), -1)
    cv2.rectangle(out, (10, 10), (30 + tw, 30 + tht + base), (40, 40, 40), th)
    cv2.putText(out, hdr, (20, 20 + tht), font, scale * 1.3, (20, 20, 20), th + 1, cv2.LINE_AA)
    if crop:
        valid = ~(img >= 254).all(axis=2)
        cols = np.where(valid.mean(axis=0) > 0.01)[0]
        rows = np.where(valid.mean(axis=1) > 0.01)[0]
        if len(cols) and len(rows):
            out = out[rows.min():rows.max() + 1, cols.min():cols.max() + 1]
    return out
