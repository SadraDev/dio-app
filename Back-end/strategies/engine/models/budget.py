"""
Account balance / risk / position sizing (ported from DIO).

Changes vs original:
  * driven by an injected `EngineConfig` instead of the global settings singleton
  * `risk_percent` now comes from the strategy config (the field we added)
  * the CHoCH / trend / time risk modifiers were removed (those flags are gone)
"""
from __future__ import annotations
from typing import Optional, Dict, Any

from ..config import EngineConfig


# Symbol pip sizes
_PIP_SIZES = {
    'EURUSD': 0.0001, 'GBPUSD': 0.0001, 'AUDUSD': 0.0001, 'NZDUSD': 0.0001,
    'USDCAD': 0.0001, 'USDCHF': 0.0001, 'EURGBP': 0.0001, 'EURAUD': 0.0001,
    'EURNZD': 0.0001, 'EURCHF': 0.0001, 'EURCAD': 0.0001, 'GBPAUD': 0.0001,
    'GBPNZD': 0.0001, 'GBPCAD': 0.0001, 'GBPCHF': 0.0001, 'AUDNZD': 0.0001,
    'AUDCAD': 0.0001, 'AUDCHF': 0.0001, 'NZDCAD': 0.0001, 'NZDCHF': 0.0001,
    'CADCHF': 0.0001,
    'USDJPY': 0.01, 'EURJPY': 0.01, 'GBPJPY': 0.01, 'AUDJPY': 0.01,
    'NZDJPY': 0.01, 'CADJPY': 0.01, 'CHFJPY': 0.01,
    'XAUUSD': 0.01, 'XAGUSD': 0.001, 'WTIUSD': 0.01, 'UKOIL': 0.01,
    'US30': 1.0, 'US500': 0.1, 'NAS100': 0.1, 'GER30': 1.0, 'UK100': 1.0, 'JPN225': 1.0,
}

# Units per standard lot
_PER_LOT = {
    'EURUSD': 100000, 'GBPUSD': 100000, 'AUDUSD': 100000, 'NZDUSD': 100000,
    'USDCAD': 100000, 'USDCHF': 100000, 'EURGBP': 100000, 'EURAUD': 100000,
    'EURNZD': 100000, 'EURCHF': 100000, 'EURCAD': 100000, 'GBPAUD': 100000,
    'GBPNZD': 100000, 'GBPCAD': 100000, 'GBPCHF': 100000, 'AUDNZD': 100000,
    'AUDCAD': 100000, 'AUDCHF': 100000, 'NZDCAD': 100000, 'NZDCHF': 100000,
    'CADCHF': 100000,
    'USDJPY': 1000, 'EURJPY': 1000, 'GBPJPY': 1000, 'AUDJPY': 1000,
    'NZDJPY': 1000, 'CADJPY': 1000, 'CHFJPY': 1000,
    'XAUUSD': 100000, 'XAGUSD': 500, 'WTIUSD': 1000, 'UKOIL': 1000,
    'US30': 1000, 'US500': 100, 'NAS100': 100, 'GER30': 1000, 'UK100': 1000, 'JPN225': 1000,
}


class Budget:
    """Manages balance, risk and position sizing for one strategy run."""

    def __init__(self, config: EngineConfig, initial_balance: Optional[float] = None,
                 initial_risk_percent: Optional[float] = None):
        self.config = config

        self.initial_balance = initial_balance or config.get("account.balance", 10000)
        self.current_balance = self.initial_balance

        # risk_percent is the config field we added.
        self.initial_risk_percent = (
            initial_risk_percent if initial_risk_percent is not None
            else config.get("risk_percent", 0.005)
        )
        self.current_risk_percent = self.initial_risk_percent

        self.pip_size = None
        self.lot_size = None
        self.min_lot_size = config.get("min_lot_size", 0.01)

    # --- conversions ---------------------------------------------------------
    def reset(self, balance: Optional[float] = None):
        self.current_balance = balance if balance is not None else self.initial_balance
        self.current_risk_percent = self.initial_risk_percent

    def apply_signal_gain(self, signal):
        self.current_balance += signal.gain

    def pips_from_diff(self, price_diff: float) -> float:
        return abs(price_diff) / self.pip_size

    def diff_from_pips(self, pips: float) -> float:
        return abs(pips) * self.pip_size

    def risk_amount(self) -> float:
        return self.current_risk_percent * self.current_balance

    def calculate_pip_size(self, symbol: str):
        if symbol is None:
            return 0
        self.pip_size = _PIP_SIZES.get(symbol.rstrip('.').upper())
        return self.pip_size

    def calculate_lot_size(self, symbol: str):
        if symbol is None:
            return 0
        self.lot_size = _PER_LOT.get(symbol.rstrip('.').upper())
        return self.lot_size

    def calculate_pip_value(self, symbol: str) -> float:
        lot_size = self.calculate_lot_size(symbol)
        pip_size = self.calculate_pip_size(symbol)
        return pip_size * lot_size

    def lots_from_diff(self, symbol: str, sl_distance: float) -> float:
        sl_distance_pips = self.pips_from_diff(sl_distance)
        if sl_distance_pips < 0:
            raise ValueError("Stop loss distance must be greater than 0")
        pip_value_per_lot = self.calculate_pip_value(symbol)
        lot_size = self.risk_amount() / (sl_distance_pips * pip_value_per_lot) if sl_distance_pips != 0 else 0
        return max(round(lot_size, 2), self.min_lot_size)

    def calculate_gain_loss(self, symbol: str, entry_price: float, exit_price: float,
                            lot_size: float, action: str) -> float:
        if action.upper() == "BUY":
            pips_moved = self.pips_from_diff(exit_price - entry_price)
            if exit_price < entry_price:
                pips_moved = -pips_moved
        else:
            pips_moved = self.pips_from_diff(entry_price - exit_price)
            if entry_price < exit_price:
                pips_moved = -pips_moved
        pip_value_per_lot = self.calculate_pip_value(symbol)
        return pips_moved * pip_value_per_lot * lot_size

    def update_risk_percent(self, signal):
        """
        Trimmed: with the CHoCH / trend / time flags removed there is no dynamic
        risk cut anymore, so risk stays at the configured `risk_percent`, capped
        by `max_risk_percent`.
        """
        self.current_risk_percent = self.initial_risk_percent
        max_risk = self.config.get("max_risk_percent", 0.05)
        self.current_risk_percent = min(self.current_risk_percent, max_risk)

    def get_summary(self) -> Dict[str, Any]:
        return {
            "initial_balance": self.initial_balance,
            "current_balance": self.current_balance,
            "net_change": self.current_balance - self.initial_balance,
            "net_change_percent": (self.current_balance - self.initial_balance) / self.initial_balance * 100
            if self.initial_balance else 0.0,
            "initial_risk_percent": self.initial_risk_percent,
            "current_risk_percent": self.current_risk_percent,
            "current_risk_amount": self.risk_amount(),
        }

    def __repr__(self):
        change = self.current_balance - self.initial_balance
        return (f"Budget(Balance: ${self.current_balance:.2f} {'+' if change >= 0 else ''}${change:.2f}, "
                f"Risk: {self.current_risk_percent:.1%})")
