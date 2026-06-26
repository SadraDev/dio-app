"""
TwoHunters strategy (ported from DIO, trimmed to default breakout + backtest).

Removed vs original:
  * recovery signals / recovery breakout
  * CHoCH detection and all strategy flags except `order_block_significance`
  * FVG detector usage, trend detector, the offline-commission / 2R / large-SLP flags
  * the heavy ReportGenerator/plotter (backtest now returns a clean JSON-able dict)

Kept: MBox envelope -> default breakout hunt -> entry/SL/TP with the FVG-scale
entry refinement, position sizing via Budget, and signal evaluation.
"""
from __future__ import annotations
from datetime import datetime, timedelta, time
from typing import Dict, List, Optional, Tuple, Any

from ..config import EngineConfig, default_config
from ..models.signal import Signal, SignalAction, SignalType
from ..models.bar import Bar
from ..models.budget import Budget
from ..indicators.breakout import BreakoutEngine
from ..indicators.mbox import MBoxAnalyzer
from ..data.fetcher import DataFetcher
from ..logger import TradingLogger


class TwoHunters:
    """
    Two Hunters strategy.

    Logic:
      1. Build the MBox session envelope (high / low).
      2. Hunt for `num_hunt_main` breakouts of that envelope in the main session.
      3. On a confirmed breakout, place entry / SL / TP and size the position.
    """

    def __init__(self, config: Optional[Dict[str, Any]] = None,
                 budget: Optional[Budget] = None, fetcher: Optional[DataFetcher] = None,
                 name: str = "TwoHunters"):
        self.config = EngineConfig(config if config is not None else default_config())
        self.name = name
        self.fetcher = fetcher or DataFetcher()
        self.budget = budget or Budget(self.config)

        self.symbol: Optional[str] = None
        self.all_bars: List[Bar] = []

        self.mbox_analyzer = MBoxAnalyzer()
        self.breakout_engine = BreakoutEngine(self.config, fetcher=self.fetcher)

        self.mbox_time = self._get_time("mbox_time")
        self.session_time = self._get_time("sessions.main")
        self.mbox_result: Dict[str, Any] = {}

        self.logger = TradingLogger.get_trading_logger()

    # --- config helpers ------------------------------------------------------
    def _get_time(self, key: str) -> Tuple[time, time]:
        cfg = self.config.get(key, {})
        start = datetime.strptime(cfg["start"], "%H:%M").time()
        end = datetime.strptime(cfg["end"], "%H:%M").time()
        return (start, end)

    @property
    def margin_pips(self) -> float:
        return self.config.get("margin_pips")

    @property
    def fvg_range(self) -> Tuple[float, float]:
        return (self.config.get("fvg.min_size_pips"), self.config.get("fvg.max_size_pips"))

    @property
    def ratios(self) -> Dict[str, float]:
        return self.config.get("ratios", {"stop_loss": 1.0, "take_profit": 2.0})

    # --- bar handling --------------------------------------------------------
    def get_mbox_bars(self, target_date: datetime) -> List[Bar]:
        start = datetime.combine(target_date.date(), self.mbox_time[0])
        end = datetime.combine(target_date.date(), self.mbox_time[1])
        return [b for b in self.all_bars if start <= b.timestamp <= end]

    def get_session_bars(self, target_date: datetime) -> List[Bar]:
        start = datetime.combine(target_date.date(), self.session_time[0])
        end = datetime.combine(target_date.date(), self.session_time[1])
        return [b for b in self.all_bars if start <= b.timestamp <= end]

    def add_bars(self, bars: List[Bar]):
        self.all_bars = list(bars)

    def _get_surrounding_bars(self, bar: Bar) -> Tuple[Optional[Bar], Optional[Bar]]:
        target = bar.timestamp
        surrounding = [b for b in self.all_bars
                       if target - timedelta(minutes=1) <= b.timestamp <= target + timedelta(minutes=1)]
        if len(surrounding) >= 3:
            return surrounding[0], surrounding[-1]
        return None, None

    # --- entry calculation ---------------------------------------------------
    def calculate_entry_details(self, action: SignalAction, signal_bar: Bar,
                                    extrema: float) -> Tuple[float, float, float, bool]:

            before_bar, after_bar = self._get_surrounding_bars(signal_bar)
            if not before_bar or not after_bar:
                before_bar = after_bar = signal_bar

            min_fvg, max_fvg = self.fvg_range

            def dynamic_fvg_scale(fvg_size_pips: float) -> float:
                if min_fvg <= fvg_size_pips <= max_fvg:
                    t = (fvg_size_pips - min_fvg) / (max_fvg - min_fvg)
                    return 0.8 - (t * 0.2)
                if fvg_size_pips <= min_fvg:
                    return 1.0
                return 0.6

            scale = 1.0
            if action == SignalAction.SELL:
                # SELL defaults to Bid price
                entry_price = signal_bar.close 

                if before_bar.bid_low > signal_bar.close:
                    fvg_size_pips = self.budget.pips_from_diff(extrema - signal_bar.bid_low)
                    scale = dynamic_fvg_scale(fvg_size_pips)
                    if scale != 1.0:
                        entry_price = extrema - abs(signal_bar.bid_low - extrema) * scale
                
                diff = self.budget.diff_from_pips(self.margin_pips)
                stop_loss = self.ratios["stop_loss"] * (extrema + diff)
                take_profit = entry_price - self.ratios["take_profit"] * abs(entry_price - stop_loss)

            else:  # BUY
                # BUY defaults to Ask price
                entry_price = signal_bar.close + (signal_bar.spread or 0.0)
                
                if signal_bar.close + (signal_bar.spread or 0.0) > before_bar.ask_high:
                    fvg_size_pips = self.budget.pips_from_diff(signal_bar.ask_high - extrema)
                    scale = dynamic_fvg_scale(fvg_size_pips)
                    if scale != 1.0:
                        entry_price = extrema + abs(extrema - signal_bar.ask_high) * scale
                
                diff = self.budget.diff_from_pips(self.margin_pips)
                stop_loss = self.ratios["stop_loss"] * (extrema - diff)
                take_profit = entry_price + self.ratios["take_profit"] * abs(entry_price - stop_loss)

            return entry_price, stop_loss, take_profit, scale < 1.0

    def create_signal(self, action: SignalAction, entry_price: float, stop_loss: float,
                      take_profit: float, timestamp: datetime) -> Signal:
        return Signal(action=action, entry_price=entry_price, stop_loss=stop_loss,
                      take_profit=take_profit, symbol=self.symbol, timestamp=timestamp,
                      signal_type=SignalType.MAIN)

    # --- signal generation ---------------------------------------------------
    def attempt_signal(self, target_date: datetime) -> Optional[Signal]:
        mbox_bars = self.get_mbox_bars(target_date)
        session_bars = self.get_session_bars(target_date)
        if not mbox_bars or len(session_bars) < 5:
            return None

        mbox_result = self.mbox_analyzer.calculate(mbox_bars)
        self.breakout_engine.symbol = self.symbol
        extrema, signal_bar, action, _, _ = self.breakout_engine.breakout(session_bars, mbox_result)
        if not signal_bar:
            return None

        action_enum = SignalAction.SELL if action == "SELL" else SignalAction.BUY
        entry_price, stop_loss, take_profit, is_order = self.calculate_entry_details(
            action_enum, signal_bar, extrema)

        signal = self.create_signal(action_enum, entry_price, stop_loss, take_profit, signal_bar.timestamp)

        self.budget.update_risk_percent(signal)
        signal.is_order = is_order

        _r = abs(signal.entry_price - signal.stop_loss)
        signal.entry_lot = self.budget.lots_from_diff(signal.symbol, _r)
        signal.stop_loss_pips = self.budget.pips_from_diff(_r)
        signal.take_profit_pips = self.budget.pips_from_diff(abs(signal.take_profit - signal.entry_price))

        return signal

    def prepare_day(self, symbol: str, target_date: datetime) -> Optional[Signal]:
        """Fetch the day's bars for one symbol, size the budget, and attempt a signal."""
        self.symbol = symbol
        day_start = datetime.combine(target_date.date(), self.mbox_time[0])
        day_end = datetime.combine(target_date.date(), self.session_time[1])
        daily_bars = self.fetcher.fetch_bars_from_mt5(day_start, day_end, symbol)

        self.budget.calculate_pip_size(symbol)
        self.budget.calculate_lot_size(symbol)
        if not daily_bars:
            return None
        self.add_bars(daily_bars)
        return self.attempt_signal(target_date)

    # --- backtest ------------------------------------------------------------
    def backtest(self, symbols: List[str], start_date: datetime, end_date: datetime) -> Dict[str, Any]:
            """
            Run a day-by-day backtest. Returns a JSON-able dict:
                { "EURUSD": [signal_dict, ...], ..., "equity_curve": [...], "summary": {...} }
            """
            results: Dict[str, Any] = {sym: [] for sym in symbols}
            all_signals = []
            days_processed = 0
            bars_processed = 0

            # Metrics Tracking
            peak = self.budget.initial_balance
            max_drawdown_pct = 0.0
            equity_curve = [{"time": start_date.isoformat(), "equity": peak}]

            current_date = start_date
            while current_date < end_date:
                if current_date.weekday() >= 5:  # skip weekends
                    current_date += timedelta(days=1)
                    continue

                day_start = datetime.combine(current_date.date(), self.mbox_time[0])
                day_end = datetime.combine(current_date.date(), self.session_time[1])

                for symbol in symbols:
                    daily_bars = self.fetcher.fetch_bars_from_mt5(day_start, day_end, symbol)
                    bars_processed += len(daily_bars)
                    self.budget.calculate_pip_size(symbol)
                    self.budget.calculate_lot_size(symbol)
                    if not daily_bars:
                        continue

                    self.symbol = symbol
                    self.add_bars(daily_bars)
                    signal = self.attempt_signal(current_date)
                    if signal:
                        signal.evaluate_signal(budget=self.budget, fetcher=self.fetcher)
                        if signal.is_completed:
                            self.budget.apply_signal_gain(signal)
                            results[symbol].append(signal.to_dict())
                            all_signals.append(signal)

                            # Update equity curve and drawdown
                            current_balance = self.budget.current_balance
                            timestamp_str = signal.timestamp.isoformat() if hasattr(signal.timestamp, 'isoformat') else str(signal.timestamp)
                            
                            equity_curve.append({
                                "time": timestamp_str,
                                "equity": current_balance
                            })
                            
                            if current_balance > peak:
                                peak = current_balance
                            else:
                                dd_pct = ((peak - current_balance) / peak) * 100
                                if dd_pct > max_drawdown_pct:
                                    max_drawdown_pct = dd_pct

                days_processed += 1
                current_date += timedelta(days=1)

            # Ensure curve is chronological if multiple symbols fired on the same day
            equity_curve.sort(key=lambda x: x["time"])

            wins = sum(1 for s in all_signals if s.outcome and s.outcome.value == "win")
            losses = sum(1 for s in all_signals if s.outcome and s.outcome.value == "loss")
            total = len(all_signals)
            gross = sum(s.gain for s in all_signals)

            results["equity_curve"] = equity_curve
            results["summary"] = {
                "symbols": symbols,
                "start_date": start_date.isoformat(),
                "end_date": end_date.isoformat(),
                "initial_balance": self.budget.initial_balance,
                "final_balance": self.budget.current_balance,
                "net_gain": self.budget.current_balance - self.budget.initial_balance,
                "total_signals": total,
                "wins": wins,
                "losses": losses,
                "win_rate": (wins / total * 100) if total else 0.0,
                "gross_gain": gross,
                "days_processed": days_processed,
                "bars_processed": bars_processed,
                "total_drawdown": max_drawdown_pct,
            }
            return results