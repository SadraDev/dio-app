"""
MBox analyzer (ported from DIO, trimmed).

The original computed trend direction/confidence via a `trend_detector` and an
extrema time-flag. Those are gone (trend detector explicitly excluded, and the
flags that consumed them were removed). The default breakout only needs the
session high (`max_val`) and low (`min_val`), so that is all we compute.
"""
from __future__ import annotations
from typing import List, Dict, Any

from ..models.bar import Bar


class MBoxAnalyzer:
    """Extracts the high/low envelope of the MBox session bars."""

    def __init__(self):
        self.results: Dict[str, Any] | None = None

    def calculate(self, bars: List[Bar]) -> Dict[str, Any]:
        if not bars:
            return {}

        all_ohlc = [(b.open, b.high, b.low, b.close) for b in bars]
        min_val = min(min(o) for o in all_ohlc)
        max_val = max(max(o) for o in all_ohlc)

        self.results = {
            "max_val": max_val,
            "min_val": min_val,
        }
        return self.results
