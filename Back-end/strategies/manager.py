"""
Live worker manager for TwoHunters.
Each "worker" is one strategy running on one symbol in its own thread.

State is held in memory but BROADCAST via WebSockets to connected clients.
"""
from __future__ import annotations
import threading
import time
import logging
from datetime import datetime, time as dtime
from typing import Dict, Optional, List, Any

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

from .engine.config import EngineConfig
from .engine.strategies.two_hunters import TwoHunters
from .engine.models.signal import SignalAction

logger = logging.getLogger("strategies.manager")

# Phase constants
HUNTING = "HUNTING_PHASE"
ORDER_PLACED = "ORDER_PLACED"
POSITION_PLACED = "POSITION_PLACED"
MONITORING = "MONITORING_SIGNAL"
DONE = "DONE"
STOPPED = "STOPPED"
PAUSED = "PAUSED"

POLL_SECONDS = 5

def _in_session(now: datetime, start: dtime, end: dtime) -> bool:
    """Handle normal and midnight-wrapping session windows."""
    t = now.time()
    if start <= end:
        return start <= t <= end
    return t >= start or t <= end

def broadcast_state(state: dict):
    """Pushes worker state updates down the WebSocket channel."""
    channel_layer = get_channel_layer()
    if channel_layer:
        async_to_sync(channel_layer.group_send)(
            "strategy_updates",
            {
                "type": "strategy_update",
                "data": state
            }
        )

class Worker:
    def __init__(self, strategy: str, symbol: str, config: Dict[str, Any], dry_run: bool = True):
        self.strategy = strategy
        self.symbol = symbol
        self.config_dict = config
        self.dry_run = dry_run

        self._kill = threading.Event()
        self._pause = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)

        self.running = True
        self.phase = HUNTING
        self.message = "Worker starting"
        self.hunt_current = 0
        self.hunt_total = int(EngineConfig(config).get("breakout.num_hunt_main", 2))
        self.session_open = False
        self.active_signal: Optional[dict] = None
        self.today = {"outcome": None, "net_gain": 0.0}
        self._day = datetime.now().date()

        self._engine = TwoHunters(config=config)

    def start(self):
        self._thread.start()

    def pause(self):
        self._pause.set()

    def resume(self):
        self._pause.clear()

    def kill(self):
        self._kill.set()

    @property
    def key(self) -> str:
        return f"{self.strategy}::{self.symbol}"

    def to_state(self) -> dict:
        return {
            "strategy": self.strategy,
            "symbol": self.symbol,
            "running": self.running,
            "paused": self._pause.is_set(),
            "phase": self.phase,
            "message": self.message,
            "hunt_current": self.hunt_current,
            "hunt_total": self.hunt_total,
            "session_open": self.session_open,
            "active_signal": self.active_signal,
            "today": self.today,
            "config": self.config_dict,
            "dry_run": self.dry_run,
            "updated_at": datetime.now().isoformat(),
        }

    def _sig_payload(self, sig) -> dict:
        return {
            "side": sig.action.value,
            "entry": sig.entry_price,
            "sl_pips": sig.stop_loss_pips or 0.0,
            "tp_pips": sig.take_profit_pips or 0.0,
            "lots": sig.entry_lot or 0.0,
            "gain": sig.gain or 0.0,
            "is_order": sig.is_order,
            "risk_free": sig.sl_adjusted_count > 0,
            "ticket": sig.ticket,
        }

    def _run(self):
        logger.info("worker %s started (dry_run=%s)", self.key, self.dry_run)
        cfg = EngineConfig(self.config_dict)
        s_start = datetime.strptime(cfg.get("sessions.main.start"), "%H:%M").time()
        s_end = datetime.strptime(cfg.get("sessions.main.end"), "%H:%M").time()

        self._set(HUNTING, f"Hunting phase 0/{self.hunt_total}, looking for setup")
        active_sig_obj = None

        while not self._kill.is_set():
            try:
                if self._pause.is_set():
                    if self.phase != PAUSED:
                        self._set(PAUSED, "Paused by user")
                    time.sleep(POLL_SECONDS)
                    continue

                now = datetime.now()

                if now.date() != self._day:
                    self._day = now.date()
                    active_sig_obj = None
                    self.active_signal = None
                    self.today = {"outcome": None, "net_gain": 0.0}
                    self._set(HUNTING, "New day, hunting for setup")

                self.session_open = _in_session(now, s_start, s_end)

                if self.phase == DONE:
                    time.sleep(POLL_SECONDS)
                    continue

                if active_sig_obj is None:
                    if not self.session_open:
                        self._set(HUNTING, "Waiting for session window")
                        time.sleep(POLL_SECONDS)
                        continue

                    self.hunt_current = min(self.hunt_current + 1, self.hunt_total)
                    self._set(HUNTING, f"Hunting phase {self.hunt_current}/{self.hunt_total}, scanning breakout")

                    sig = self._engine.prepare_day(self.symbol, now)
                    if sig is None:
                        time.sleep(POLL_SECONDS)
                        continue

                    active_sig_obj = sig
                    self.active_signal = self._sig_payload(sig)
                    if not self.dry_run:
                        self._place_order(sig)

                    if sig.is_order:
                        self._set(ORDER_PLACED, f"Setup found, pending {sig.action.value} order placed")
                    else:
                        self._set(POSITION_PLACED, f"Setup found, {sig.action.value} position opened")
                    time.sleep(POLL_SECONDS)
                    continue

                self._monitor(active_sig_obj)
                time.sleep(POLL_SECONDS)

            except Exception:
                import traceback
                logger.error("worker %s error:\n%s", self.key, traceback.format_exc())
                time.sleep(POLL_SECONDS)

        self.running = False
        self._set(STOPPED, "Stopped by user")
        logger.info("worker %s stopped", self.key)

    def _monitor(self, sig):
        if self.phase != MONITORING:
            self._set(MONITORING, "Monitoring signal")

        price = self._engine.fetcher.get_current_price(self.symbol)
        if not price:
            return

        cur = price["bid"] if sig.action == SignalAction.SELL else price["ask"]
        gain = self._engine.budget.calculate_gain_loss(
            self.symbol, sig.entry_price, cur, sig.entry_lot or 0.0, sig.action.value)
        sig.gain = gain
        self.active_signal = self._sig_payload(sig)

        hit_tp = (sig.action == SignalAction.SELL and cur <= sig.take_profit) or \
                 (sig.action == SignalAction.BUY and cur >= sig.take_profit)
        hit_sl = (sig.action == SignalAction.SELL and cur >= sig.stop_loss) or \
                 (sig.action == SignalAction.BUY and cur <= sig.stop_loss)

        if hit_tp or hit_sl:
            outcome = "win" if hit_tp else "loss"
            self.today = {"outcome": outcome, "net_gain": self.today["net_gain"] + gain}
            if not self.dry_run:
                self._close_position(sig)
            self.active_signal = None
            self._set(DONE, f"Signal closed {outcome.upper()} "
                            f"{'+' if gain >= 0 else '-'}${abs(gain):.2f} - done for today")
            return

        self._set(MONITORING, f"Monitoring signal, floating "
                              f"{'+' if gain >= 0 else '-'}${abs(gain):.2f}")

    def _place_order(self, sig):
        try:
            from marketdata.services.mt5_service import MT5Service
            service = MT5Service()
            side = sig.action.value.lower()
            if sig.is_order:
                side = f"{side}_limit"
            result = service.order_send(
                symbol=self.symbol, volume=sig.entry_lot, side=side,
                price=sig.entry_price if sig.is_order else None,
                sl=sig.stop_loss, tp=sig.take_profit)
            sig.ticket = getattr(result, "order", None)
            logger.info("worker %s placed order ticket=%s", self.key, sig.ticket)
        except Exception:
            import traceback
            logger.error("worker %s order failed:\n%s", self.key, traceback.format_exc())

    def _close_position(self, sig):
        try:
            if sig.ticket:
                from marketdata.services.mt5_service import MT5Service
                MT5Service().close_position(ticket=sig.ticket)
        except Exception:
            import traceback
            logger.error("worker %s close failed:\n%s", self.key, traceback.format_exc())

    def _set(self, phase: str, message: str):
        self.phase = phase
        self.message = message
        # Broadcast immediately upon state mutation
        broadcast_state(self.to_state())


class WorkerManager:
    _instance: Optional["WorkerManager"] = None
    _lock = threading.Lock()

    def __init__(self):
        self._workers: Dict[str, Worker] = {}

    @classmethod
    def instance(cls) -> "WorkerManager":
        with cls._lock:
            if cls._instance is None:
                cls._instance = WorkerManager()
        return cls._instance

    def start(self, symbol: str, config: Dict[str, Any], strategy: str = "TwoHunters",
              dry_run: bool = True) -> dict:
        key = f"{strategy}::{symbol}"
        existing = self._workers.get(key)
        if existing and existing.running and not existing._kill.is_set():
            return existing.to_state()
        worker = Worker(strategy, symbol, config, dry_run=dry_run)
        self._workers[key] = worker
        worker.start()
        return worker.to_state()

    def pause(self, key: str) -> Optional[dict]:
        w = self._workers.get(key)
        if not w:
            return None
        w.pause()
        return w.to_state()

    def resume(self, key: str) -> Optional[dict]:
        w = self._workers.get(key)
        if not w:
            return None
        w.resume()
        return w.to_state()

    def kill(self, key: str) -> Optional[dict]:
        w = self._workers.get(key)
        if not w:
            return None
        w.kill()
        state = w.to_state()
        state["running"] = False
        state["phase"] = STOPPED
        self._workers.pop(key, None)
        
        # Broadcast the killed state so UI drops it
        broadcast_state(state)
        return state

    def snapshot(self) -> List[dict]:
        return [w.to_state() for w in self._workers.values()]