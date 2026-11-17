"""Kiértékelés a kézi (nézőkés) eredményekhez képest.

Használat:  python tools/evaluate.py [--out OUTDIR]
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import cv2
import numpy as np
from scipy.optimize import linear_sum_assignment

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from bullseye_engine.annotate import annotate  # noqa: E402
from bullseye_engine.pipeline import analyze  # noqa: E402
from bullseye_engine.target import TargetSpec  # noqa: E402

TESTDATA = ROOT.parent / "testdata"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=None)
    args = ap.parse_args()
    gt = json.loads((TESTDATA / "ground_truth.json").read_text(encoding="utf-8"))
    spec = TargetSpec.load("mdlsz_gyorspont")
    ok_all = True
    for name, g in gt.items():
        img = cv2.imread(str(TESTDATA / name))
        res = analyze(img, spec, expected=g["shot_count"])
        pred = np.array([[s.x, s.y] for s in res.shots])
        truth = np.array([[s["x"], s["y"]] for s in g["shots"]])
        C = np.hypot(pred[:, None, 0] - truth[None, :, 0], pred[:, None, 1] - truth[None, :, 1])
        r, c = linear_sum_assignment(C)
        lim = res.calibration["ring_spacing_px"] * 0.7
        matched = [(i, j) for i, j in zip(r, c) if C[i, j] <= lim]
        wrong = [(res.shots[i], g["shots"][j]) for i, j in matched
                 if res.shots[i].score != g["shots"][j]["score"]]
        missed = len(truth) - len(matched)
        extra = len(pred) - len(matched)
        diff = res.total - g["total"]
        ok = abs(diff) <= 1
        ok_all &= ok
        flagged_wrong = sum(1 for p, _ in wrong if p.borderline or p.uncertain)
        print(f"{name}: összesen {res.total} (kézi {g['total']}, eltérés {diff:+d}) "
              f"{'OK' if ok else 'HIBA'} | lövés {len(res.shots)}/{g['shot_count']} "
              f"| párosítva {len(matched)}, kimaradt {missed}, felesleges {extra} "
              f"| eltérő pont {len(wrong)} (ebből jelölt {flagged_wrong})")
        for p, t in wrong:
            print(f"   #{p.index}: gép {p.score}, kézi {t['score']}  rés {p.gap_mm:.1f} mm "
                  f"{'[határeset]' if p.borderline else ''}{'[bizonytalan]' if p.uncertain else ''}")
        for w in res.warnings:
            print("   ! " + w)
        if args.out:
            out = Path(args.out)
            out.mkdir(parents=True, exist_ok=True)
            cv2.imwrite(str(out / name.replace(".png", "_kiertekelt.png")), annotate(img, res))
            (out / name.replace(".png", ".json")).write_text(
                json.dumps(res.to_dict(), ensure_ascii=False, indent=1), encoding="utf-8")
    print("ELFOGADVA" if ok_all else "NEM FELEL MEG")
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main())
