"""Price bar / candlestick model (ported from DIO, unchanged behaviour)."""
from __future__ import annotations
from datetime import datetime
from enum import Enum


class TrendDirection(Enum):
    UPTREND = "uptrend"
    DOWNTREND = "downtrend"
    NEUTRAL = "neutral"


class Bar:
    """Represents a single price bar/candlestick."""

    def __init__(self, timestamp: datetime, open_price: float, high: float,
                 low: float, close: float, volume: int = 0):
        self.timestamp = timestamp
        self.open = open_price
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume

        # Bid/ask sides (filled by the fetcher using the historical spread).
        self.bid_high = None
        self.ask_high = None
        self.bid_low = None
        self.ask_low = None
        self.spread = None

        self._calculate_attributes()

    def _calculate_attributes(self):
        self.body = abs(self.close - self.open)
        self.range = self.high - self.low
        self.upper_wick = self.high - max(self.open, self.close)
        self.lower_wick = min(self.open, self.close) - self.low
        self.top = max(self.open, self.close)
        self.bottom = min(self.open, self.close)

        self.is_bullish = self.close > self.open
        self.is_bearish = self.close < self.open
        self.is_doji = self.close == self.open

        self._classify_candle()

    def _classify_candle(self):
        self.is_weak = False
        self.is_head_down = False
        self.is_head_up = False

        if self.body == 0:
            self.is_weak = True
            self.is_doji = True
        elif self.range > 0:
            body_to_range_ratio = self.body / self.range
            if body_to_range_ratio < 0.3:
                self.is_weak = True
                if self.upper_wick >= 2 * self.lower_wick:
                    self.is_head_down = True
                elif self.lower_wick >= 2 * self.upper_wick:
                    self.is_head_up = True
                else:
                    self.is_doji = True
        else:
            self.range = 0.0000001

    @property
    def midpoint(self) -> float:
        return (self.high + self.low) / 2

    @property
    def typical_price(self) -> float:
        return (self.high + self.low + self.close) / 3

    @property
    def trendy(self) -> TrendDirection:
        if self.is_doji:
            return TrendDirection.NEUTRAL

        upperwick_to_range = self.upper_wick / self.range if self.upper_wick > 0 else 0.001
        lowerwick_to_range = self.lower_wick / self.range if self.lower_wick > 0 else 0.001

        if upperwick_to_range > 0.55:
            return TrendDirection.DOWNTREND
        if lowerwick_to_range > 0.55:
            return TrendDirection.UPTREND

        if self.is_weak:
            if lowerwick_to_range / upperwick_to_range >= 3.5:
                return TrendDirection.UPTREND
            if upperwick_to_range / lowerwick_to_range >= 3.5:
                return TrendDirection.DOWNTREND
        else:
            if lowerwick_to_range / upperwick_to_range >= 2.0:
                return TrendDirection.UPTREND
            if upperwick_to_range / lowerwick_to_range >= 2.0:
                return TrendDirection.DOWNTREND

        return TrendDirection.NEUTRAL

    @property
    def is_uptrend(self):
        return self.trendy == TrendDirection.UPTREND

    @property
    def is_downtrend(self):
        return self.trendy == TrendDirection.DOWNTREND

    def __repr__(self):
        direction = "U" if self.is_bullish else "D" if self.is_bearish else "-"
        return (f"Bar({self.timestamp.strftime('%Y-%m-%d %H:%M')} | "
                f"O:{self.open:.5f} H:{self.high:.5f} L:{self.low:.5f} C:{self.close:.5f} | "
                f"{direction} V:{self.volume})")

    def __str__(self):
        return self.__repr__()

    def __eq__(self, other):
        if not isinstance(other, Bar):
            return NotImplemented
        return (self.timestamp == other.timestamp and self.open == other.open and
                self.high == other.high and self.low == other.low and
                self.close == other.close and self.volume == other.volume)

    def __hash__(self):
        return hash((self.timestamp, self.open, self.high, self.low, self.close, self.volume))

    def __lt__(self, other):
        if not isinstance(other, Bar):
            return NotImplemented
        return self.timestamp < other.timestamp

    def __gt__(self, other):
        if not isinstance(other, Bar):
            return NotImplemented
        return self.timestamp > other.timestamp

    def to_dict(self) -> dict:
        return {
            "timestamp": self.timestamp.isoformat(),
            "open": self.open, "high": self.high, "low": self.low,
            "close": self.close, "volume": self.volume,
        }
