"""
Trading signal model (ported from DIO).

Changes vs original:
  * uses the injected DataFetcher / Budget instead of global settings
  * removed the heavy log_signal_event calls (kept the evaluation logic intact)
  * the trend / time_flag / fake_CHoCH attributes remain only as inert metadata
    (the flags that consumed them were removed)
"""
from __future__ import annotations
from datetime import datetime, timedelta
from typing import Optional, TYPE_CHECKING
from enum import Enum

if TYPE_CHECKING:
    from .budget import Budget
    from ..data.fetcher import DataFetcher


class SignalAction(Enum):
    BUY = "BUY"
    SELL = "SELL"


class SignalOutcome(Enum):
    WIN = "win"
    LOSS = "loss"
    PENDING = "pending"
    FORCE_STOPED = "force_stoped"


class SignalType(Enum):
    MAIN = "main"
    RECOVERY = "recovery"


class Signal:
    def __init__(self, action: SignalAction, entry_price: float, stop_loss: float,
                 take_profit: float, symbol: str, timestamp: datetime,
                 signal_type: SignalType = SignalType.MAIN,
                 take_profit_pips: Optional[float] = None,
                 stop_loss_pips: Optional[float] = None, entry_lot: Optional[float] = None,
                 gain: Optional[float] = None, ticket: Optional[int] = None):
        self.action = action if isinstance(action, SignalAction) else SignalAction(action)
        self.symbol = symbol
        self.timestamp = timestamp
        self.signal_type = signal_type

        self.entry_price = entry_price
        self.stop_loss = stop_loss
        self.take_profit = take_profit

        self.initial_entry_price = entry_price
        self.initial_stop_loss = stop_loss
        self.initial_take_profit = take_profit

        self.entry_lot = entry_lot
        self.stop_loss_pips = stop_loss_pips
        self.take_profit_pips = take_profit_pips

        self.outcome: Optional[SignalOutcome] = SignalOutcome.PENDING
        self.outcome_timestamp: Optional[datetime] = None
        self.exit_pips: Optional[float] = None
        self.exit_price: Optional[float] = None
        self.gain = gain if gain else 0.0

        self.ticket = ticket
        self.commission = None
        self.is_order: bool = False

        # Inert metadata (no flags consume these anymore).
        self.trend = None
        self.fake_CHoCH = None
        self.time_flag = None
        self.used_flag = False
        self.sl_adjusted_count = 0

    # --- properties ----------------------------------------------------------
    @property
    def is_main(self) -> bool:
        return self.signal_type == SignalType.MAIN

    @property
    def is_buy(self) -> bool:
        return self.action == SignalAction.BUY

    @property
    def is_sell(self) -> bool:
        return self.action == SignalAction.SELL

    @property
    def is_pending(self) -> bool:
        return self.outcome is None or self.outcome == SignalOutcome.PENDING

    @property
    def is_completed(self) -> bool:
        return self.outcome in [SignalOutcome.WIN, SignalOutcome.LOSS, SignalOutcome.FORCE_STOPED]

    def reward_ratio(self) -> float:
        if not self.stop_loss_pips or self.stop_loss_pips <= 0 or self.take_profit_pips is None:
            return 0.0
        return abs(self.take_profit_pips) / abs(self.stop_loss_pips)

    def update_outcome(self, outcome: SignalOutcome, gain: float, timestamp: Optional[datetime] = None):
        self.outcome = outcome
        self.gain += gain
        self.outcome_timestamp = timestamp or datetime.now()

    # --- evaluation ----------------------------------------------------------
    def evaluate_signal(self, budget: "Budget", fetcher: "DataFetcher" = None,
                        force_stop_dt: datetime = None, max_fetch_attempts: int = 50) -> None:
        """
        Walk forward through M1 bars (fetched on demand) until the signal hits
        TP or SL, mirroring the original DIO single-loop evaluator.
        """
        if fetcher is None:
            from ..data.fetcher import DataFetcher
            fetcher = DataFetcher()

        fetch_attempts = 1
        commission_value = budget.config.get("commission", 0.0)
        self.commission = (self.entry_lot or 0.0) * commission_value
        self.gain -= self.commission

        while not self.is_completed and fetch_attempts <= max_fetch_attempts:
            evaluation_bars = fetcher.fetch_bars_from_mt5(
                start_dt=self.timestamp + timedelta(minutes=1),
                end_dt=self.timestamp + timedelta(hours=24 * fetch_attempts),
                symbol=self.symbol,
            )

            if not evaluation_bars:
                if fetch_attempts < max_fetch_attempts:
                    fetch_attempts += 1
                    continue

            # Pending order: wait until price touches the entry level.
            if self.is_order:
                touched_bar = None
                for bar in evaluation_bars:
                    if self.action == SignalAction.SELL and bar.bid_high >= self.entry_price:
                        touched_bar = bar
                        break
                    if self.action == SignalAction.BUY and bar.ask_low <= self.entry_price:
                        touched_bar = bar
                        break
                if not touched_bar:
                    if fetch_attempts < max_fetch_attempts:
                        fetch_attempts += 1
                        continue
                    break
                evaluation_bars = [b for b in evaluation_bars if b.timestamp > touched_bar.timestamp]

            sell_tp_triggered = False
            buy_tp_triggered = False
            for bar in evaluation_bars:
                if force_stop_dt and bar.timestamp >= force_stop_dt:
                    self.exit_price = bar.open
                    action = "SELL" if self.action == SignalAction.SELL else "BUY"
                    actual_gain = budget.calculate_gain_loss(
                        self.symbol, self.entry_price, self.exit_price, self.entry_lot, action)
                    self.update_outcome(SignalOutcome.FORCE_STOPED, actual_gain, bar.timestamp)
                    break

                if self.action == SignalAction.SELL:
                    if bar.ask_low <= self.take_profit:
                        sell_tp_triggered = True
                        self.exit_price = self.take_profit
                        gain = budget.calculate_gain_loss(self.symbol, self.entry_price, self.exit_price, self.entry_lot, "SELL")
                        self.update_outcome(SignalOutcome.WIN, gain, bar.timestamp)
                    if bar.ask_high >= self.stop_loss:
                        self.exit_price = self.stop_loss
                        loss = budget.calculate_gain_loss(self.symbol, self.entry_price, self.stop_loss, self.entry_lot, "SELL")
                        self.update_outcome(SignalOutcome.LOSS, loss, bar.timestamp)
                    if bar.ask_low <= self.initial_take_profit and not sell_tp_triggered:
                        sell_tp_triggered = True
                        self.entry_lot = self.entry_lot / 2
                        self.exit_price = self.initial_take_profit
                        self.gain += budget.calculate_gain_loss(self.symbol, self.entry_price, self.exit_price, self.entry_lot, "SELL")

                elif self.action == SignalAction.BUY:
                    if bar.bid_high >= self.take_profit:
                        buy_tp_triggered = True
                        self.exit_price = self.take_profit
                        gain = budget.calculate_gain_loss(self.symbol, self.entry_price, self.take_profit, self.entry_lot, "BUY")
                        self.update_outcome(SignalOutcome.WIN, gain, bar.timestamp)
                    if bar.bid_low <= self.stop_loss:
                        self.exit_price = self.stop_loss
                        loss = budget.calculate_gain_loss(self.symbol, self.entry_price, self.stop_loss, self.entry_lot, "BUY")
                        self.update_outcome(SignalOutcome.LOSS, loss, bar.timestamp)
                    if bar.bid_high >= self.initial_take_profit and not buy_tp_triggered:
                        buy_tp_triggered = True
                        self.entry_lot = self.entry_lot / 2
                        self.gain += budget.calculate_gain_loss(self.symbol, self.entry_price, self.initial_take_profit, self.entry_lot, "BUY")

                if self.is_completed:
                    if buy_tp_triggered or sell_tp_triggered:
                        self.entry_lot = self.entry_lot * 2  # restore for reporting
                    break

            if fetch_attempts < max_fetch_attempts and not self.is_completed:
                fetch_attempts += 1
            else:
                break

    # --- serialization -------------------------------------------------------
    def to_dict(self) -> dict:
        return {
            "action": self.action.value,
            "symbol": self.symbol,
            "timestamp": self.timestamp.isoformat(),
            "signal_type": self.signal_type.value,
            "entry_price": self.entry_price,
            "stop_loss": self.stop_loss,
            "take_profit": self.take_profit,
            "initial_take_profit": self.initial_take_profit,
            "entry_lot": self.entry_lot,
            "stop_loss_pips": self.stop_loss_pips,
            "take_profit_pips": self.take_profit_pips,
            "outcome": self.outcome.value if self.outcome else None,
            "outcome_timestamp": self.outcome_timestamp.isoformat() if self.outcome_timestamp else None,
            "exit_price": self.exit_price,
            "gain": self.gain,
            "ticket": self.ticket,
            "commission": self.commission,
            "is_order": self.is_order,
            "is_complete": self.is_completed,
        }

    def __repr__(self):
        outcome_str = f" {self.outcome.value.upper()}" if self.outcome else " PENDING"
        lot = self.entry_lot if self.entry_lot is not None else 0.0
        return (f"Signal({self.timestamp.strftime('%Y-%m-%d %H:%M')} {self.symbol} {self.action.value} "
                f"@ {self.entry_price:.5f} Lot:{lot:.2f}{outcome_str} Gain:${self.gain:.2f})")
