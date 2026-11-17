import json
import sys
from pathlib import Path

import cv2
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from bullseye_engine.pipeline import analyze  # noqa: E402
from bullseye_engine.target import TargetSpec  # noqa: E402

TESTDATA = ROOT.parent / "testdata"
SPEC = TargetSpec.load("mdlsz_gyorspont")


def test_ring_geometry():
    assert SPEC.ring_radius(13) == 1
    assert SPEC.ring_radius(6) == 8          # black disk edge
    assert SPEC.ring_radius(11) == 3         # white inner disk edge
    assert abs(SPEC.pellet_radius - 0.28) < 0.01


def test_line_touch_rule():
    rp = SPEC.pellet_radius
    # pellet edge exactly on the 13 line -> 13
    assert SPEC.score(1 + rp)[0] == 13
    # just outside -> 12
    assert SPEC.score(1 + rp + 0.01)[0] == 12
    # centre in the 7 ring but edge touching the 8 line -> 8
    assert SPEC.score(6 + rp * 0.9)[0] == 8


GT = json.loads((TESTDATA / "ground_truth.json").read_text(encoding="utf-8"))


@pytest.mark.parametrize("name", sorted(GT))
def test_total_within_one_point(name):
    g = GT[name]
    res = analyze(cv2.imread(str(TESTDATA / name)), SPEC, expected=g["shot_count"])
    assert len(res.shots) == g["shot_count"]
    assert abs(res.total - g["total"]) <= 1
