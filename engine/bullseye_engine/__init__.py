"""Lőlap-kiértékelő motor (prototípus).

Fő belépési pont: :func:`bullseye_engine.pipeline.analyze`.
"""
from .pipeline import Result, Shot, analyze  # noqa: F401
from .target import TargetSpec  # noqa: F401
