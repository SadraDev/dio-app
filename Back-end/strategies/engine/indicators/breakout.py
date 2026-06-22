"""
Breakout detection engine (ported from DIO).

Trimmed to the DEFAULT breakout only -- the recovery / custom branches and all
FVG-nearby logic were removed (recovery, CHoCH and FVG are explicitly out of
scope). The `fvg_nearby` short-circuit in the original already returned False,
so the default behaviour is preserved exactly.
"""
from __future__ import annotations
from typing import List, Optional, Tuple
from datetime import datetime, time, timedelta

from ..models.bar import Bar
from ..config import EngineConfig
from ..data.fetcher import DataFetcher


class BreakoutEngine:
    """Identifies default breakout signals on the main session timeframe."""

    def __init__(self, config: EngineConfig, num_hunt: int = 2, symbol: str = "",
                 fetcher: Optional[DataFetcher] = None):
        self.config = config
        self.num_hunt = num_hunt
        self.symbol = symbol
        self.fetcher = fetcher or DataFetcher()

    def _get_threshold_time(self) -> time:
        end_time = datetime.strptime(self.config.get("mbox_time.end"), "%H:%M")
        return (end_time + timedelta(minutes=60)).time()

    def breakout(self, session_bars: List[Bar], mbox_result: dict
                 ) -> Tuple[Optional[float], Optional[Bar], Optional[str], Optional[Bar], Optional[float]]:
        """Public entry point (default breakout)."""
        self.num_hunt = self.config.get("breakout.num_hunt_main", 2)
        return self.default(session_bars, mbox_result)

    def default(self, session_bars: List[Bar], box: dict
                ) -> Tuple[Optional[float], Optional[Bar], Optional[str], Optional[Bar], Optional[float]]:
        lookahead = 1
        if not session_bars or not box:
            return None, None, None, None, None

        min_val = box.get("min_val")
        max_val = box.get("max_val")
        if min_val is None or max_val is None:
            return None, None, None, None, None

        breakout_stage_up = 0
        breakout_stage_down = 0

        # First M15 hunt timestamp gate (kept from the original).
        start = session_bars[0].timestamp
        end = session_bars[-1].timestamp
        _15_bars = self.fetcher.fetch_bars_from_mt5(start, end, self.symbol, "M15")
        _15_first_hunt_timestamp = None
        _15_triggered = True
        _threshold_time_triggered = True

        m = len(_15_bars)
        for i, bar in enumerate(_15_bars):
            if i + lookahead >= m:
                break
            is_local_max = all(bar.high > _15_bars[j].high for j in range(i + 1, min(i + 1 + lookahead, m)))
            is_local_min = all(bar.low < _15_bars[j].low for j in range(i + 1, min(i + 1 + lookahead, m)))
            if is_local_max and bar.high > max_val:
                _15_first_hunt_timestamp = bar.timestamp
                break
            elif is_local_min and bar.low < min_val:
                _15_first_hunt_timestamp = bar.timestamp
                break

        def valid(bar: Bar) -> bool:
            if _15_first_hunt_timestamp is None:
                return False
            return bar.timestamp > _15_first_hunt_timestamp

        n = len(session_bars)
        up_num_hunt = self.num_hunt
        down_num_hunt = self.num_hunt
        for i, bar in enumerate(session_bars):
            if i + lookahead >= n:
                break

            current_max = bar.high
            current_min = bar.low
            is_local_max = all(current_max > session_bars[j].high for j in range(i + 1, min(i + 1 + lookahead, n)))
            is_local_min = all(current_min < session_bars[j].low for j in range(i + 1, min(i + 1 + lookahead, n)))

            if is_local_max and current_max > max_val:
                breakout_stage_up += 1
                max_val = current_max
                if breakout_stage_up >= up_num_hunt:
                    if bar.timestamp.time() < self._get_threshold_time() and not _threshold_time_triggered:
                        up_num_hunt += 1
                        _threshold_time_triggered = True
                        continue
                    signal_bar = self.find_signal_bar(session_bars, bar, "SELL")
                    if signal_bar:
                        if not _15_triggered and not valid(bar):
                            up_num_hunt += 1
                            _15_triggered = True
                            continue
                        extrema = max(max_val, self.find_extrema_between_two_bars(bar, signal_bar, session_bars, "SELL"))
                        return extrema, signal_bar, "SELL", bar, None
                    else:
                        up_num_hunt += 1
                        continue

            elif is_local_min and current_min < min_val:
                breakout_stage_down += 1
                min_val = current_min
                if breakout_stage_down >= down_num_hunt:
                    if bar.timestamp.time() < self._get_threshold_time() and not _threshold_time_triggered:
                        down_num_hunt += 1
                        _threshold_time_triggered = True
                        continue
                    signal_bar = self.find_signal_bar(session_bars, bar, "BUY")
                    if signal_bar:
                        if not _15_triggered and not valid(bar):
                            down_num_hunt += 1
                            _15_triggered = True
                            continue
                        extrema = min(min_val, self.find_extrema_between_two_bars(bar, signal_bar, session_bars, "BUY"))
                        return extrema, signal_bar, "BUY", bar, None
                    else:
                        down_num_hunt += 1
                        continue

        return None, None, None, None, None

    def find_signal_bar(self, bars: List[Bar], hunter_bar: Bar, direction: str,
                        look_ahead: int = 3) -> Optional[Bar]:
        try:
            idx = bars.index(hunter_bar)
        except ValueError:
            return None

        cond = True if direction == "BUY" else False
        counter = 0
        for i in range(idx, len(bars)):
            this_bar = bars[i]
            if counter == look_ahead:
                break
            if this_bar.is_weak and idx != i:
                counter += 1
                continue

            if this_bar == hunter_bar:
                search_idx = idx - 1
                while search_idx >= 0 and (bars[search_idx].is_bullish == cond or bars[search_idx].is_weak):
                    search_idx -= 1
                to_engulf_bar = bars[search_idx] if search_idx >= 0 else bars[0]
                if self._is_order_bar(to_engulf_bar, this_bar, direction):
                    return this_bar

            if this_bar != hunter_bar:
                counter += 1
                search_idx = idx
                while search_idx >= 0 and (bars[search_idx].is_bullish == cond or bars[search_idx].is_weak):
                    search_idx -= 1
                to_engulf_bar = bars[search_idx] if search_idx >= 0 else bars[0]
                signal = self._is_order_bar(to_engulf_bar, this_bar, direction)
                if signal:
                    return signal
        return None

    def _is_order_bar(self, prev_bar: Bar, this_bar: Bar, direction: str) -> Optional[Bar]:
        _m = self.config.get("flags.order_block_significance")
        if direction == "SELL":
            if this_bar.close < prev_bar.low - (prev_bar.range * _m) and this_bar.is_bearish:
                return this_bar
        elif direction == "BUY":
            if this_bar.close > prev_bar.high + (prev_bar.range * _m) and this_bar.is_bullish:
                return this_bar
        return None

    def find_extrema_between_two_bars(self, hunter_bar: Bar, signal_bar: Bar,
                                      bars: List[Bar], action: str) -> float:
        extrema_bars = [b for b in bars if hunter_bar.timestamp <= b.timestamp <= signal_bar.timestamp]
        if not extrema_bars:
            return hunter_bar.high if action == "SELL" else hunter_bar.low
        if action == "SELL":
            return max(extrema_bars, key=lambda b: b.bid_high).bid_high
        elif action == "BUY":
            return min(extrema_bars, key=lambda b: b.ask_low).ask_low
        return 0.0
