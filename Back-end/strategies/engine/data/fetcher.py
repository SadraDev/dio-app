"""
MT5 data fetcher (ported from DIO).

Key difference from the original: it does NOT call ``mt5.shutdown()`` after each
fetch. The Django process keeps a single shared MT5 connection alive (marketdata
uses it for the live chart / account feed); tearing it down here would disrupt
those. ``mt5.initialize()`` is idempotent, so we just make sure it is up.

MetaTrader5 is imported lazily so the module can be imported on non-Windows
hosts (e.g. for migrations / tests) without the package installed.
"""
from __future__ import annotations
from datetime import datetime
from typing import List, Optional

from ..models.bar import Bar


def _mt5():
    import MetaTrader5 as mt5  # lazy import (Windows-only package)
    return mt5


class DataFetcher:
    """Fetches OHLC bars (with bid/ask sides) directly from MetaTrader 5."""

    def __init__(self):
        self._tf_map = None

    def _timeframe_map(self):
        if self._tf_map is None:
            mt5 = _mt5()
            self._tf_map = {
                "M1": mt5.TIMEFRAME_M1, "M5": mt5.TIMEFRAME_M5, "M15": mt5.TIMEFRAME_M15,
                "M30": mt5.TIMEFRAME_M30, "H1": mt5.TIMEFRAME_H1, "H4": mt5.TIMEFRAME_H4,
                "H8": mt5.TIMEFRAME_H8, "D1": mt5.TIMEFRAME_D1,
            }
        return self._tf_map

    def ensure_connection(self) -> bool:
        mt5 = _mt5()
        if not mt5.initialize():
            raise RuntimeError("Failed to initialize MetaTrader 5 connection")
        return True

    def fetch_bars_from_mt5(self, start_dt: datetime, end_dt: datetime, symbol: str,
                            timeframe: Optional[str] = None) -> List[Bar]:
        mt5 = _mt5()
        tf = timeframe or "M1"
        self.ensure_connection()

        tf_enum = self._timeframe_map().get(tf, mt5.TIMEFRAME_M1)
        rates = mt5.copy_rates_range(symbol, tf_enum, start_dt, end_dt)
        if rates is None or len(rates) == 0:
            return []

        info = mt5.symbol_info(symbol)
        point = info.point if info else 0.00001

        bars: List[Bar] = []
        for rate in rates:
            bid_high = float(rate["high"])
            bid_low = float(rate["low"])
            spread = float(rate["spread"]) * point
            bar = Bar(
                timestamp=datetime.fromtimestamp(int(rate["time"])),
                open_price=float(rate["open"]),
                high=bid_high, low=bid_low, close=float(rate["close"]),
                volume=int(rate["tick_volume"]),
            )
            bar.bid_high = bid_high
            bar.ask_high = bid_high + spread
            bar.bid_low = bid_low
            bar.ask_low = bid_low + spread
            bar.spread = spread
            bars.append(bar)
        return bars

    def get_current_price(self, symbol: str) -> Optional[dict]:
        mt5 = _mt5()
        self.ensure_connection()
        tick = mt5.symbol_info_tick(symbol)
        if not tick:
            return None
        return {"bid": tick.bid, "ask": tick.ask,
                "time": datetime.fromtimestamp(tick.time),
                "spread": abs(tick.bid - tick.ask)}
