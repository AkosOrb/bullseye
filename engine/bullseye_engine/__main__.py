"""Parancssori használat:

    python -m bullseye_engine FOTO.jpg [--shots 15] [--target mdlsz_gyorspont] [--out KIMENET_MAPPA]

Kiírja a lövéseket és az összpontszámot, és elmenti a jelölt képet és a
JSON eredményt.
"""
import argparse
import json
import sys
from pathlib import Path

import cv2

from .annotate import annotate
from .calibrate import CalibrationError
from .pipeline import analyze
from .target import TargetSpec


def main(argv=None):
    ap = argparse.ArgumentParser(prog="bullseye_engine", description="Lőlap kiértékelése fotóról")
    ap.add_argument("image")
    ap.add_argument("--shots", type=int, default=15, help="lövésszám (0 = ismeretlen)")
    ap.add_argument("--target", default="mdlsz_gyorspont")
    ap.add_argument("--out", default=".")
    a = ap.parse_args(argv)
    img = cv2.imread(a.image)
    if img is None:
        print(f"Nem olvasható kép: {a.image}", file=sys.stderr)
        return 2
    spec = TargetSpec.load(a.target)
    try:
        res = analyze(img, spec, expected=a.shots or None)
    except CalibrationError as e:
        print(f"Kalibrálási hiba: {e}", file=sys.stderr)
        return 3
    print(f"{len(res.shots)} lövés, összesen {res.total} pont")
    for s in res.shots:
        flag = " (ellenőrizendő: " + s.note + ")" if (s.borderline or s.uncertain) else ""
        print(f"  {s.index:2d}. {s.score:2d} pont{flag}")
    for w in res.warnings:
        print("! " + w)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    stem = Path(a.image).stem
    cv2.imwrite(str(out / f"{stem}_kiertekelt.png"), annotate(img, res))
    (out / f"{stem}.json").write_text(json.dumps(res.to_dict(), ensure_ascii=False, indent=1),
                                      encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
