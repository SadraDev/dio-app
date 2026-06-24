"""
Live worker manager for TwoHunters.
Each "worker" is one strategy running on one symbol in its own thread.

State is held in memory and fetched via standard HTTP GET polling.
"""
from __future__ import annotations
import MetaTrader5 as mt5
import threading
import time
import logging
import uuid
from collections import deque
from datetime import datetime, time as dtime
from typing import Dict, Optional, List, Any
from .engine.config import EngineConfig
from .engine.strategies.two_hunters import TwoHunters
from .engine.models.signal import SignalAction

logger = logging.getLogger("strategies.manager")

# Phase constants
HUNTING = "HUNTING_PHASE"
MBOX_STILL_FORMING = "MBOX_STILL_FORMING"
ORDER_PLACED = "ORDER_PLACED"
POSITION_PLACED = "POSITION_PLACED"
MONITORING = "MONITORING_SIGNAL"
DONE = "DONE"
STOPPED = "STOPPED"
PAUSED = "PAUSED"

POLL_SECONDS = 1

def _in_session(now: datetime, start: dtime, end: dtime) -> bool:
    """Handle normal and midnight-wrapping session windows."""
    t = now.time()
    if start <= end:
        return start <= t <= end
    return t >= start or t <= end

class Worker:
    def __init__(self, strategy: str, symbol: str, config: Dict[str, Any]):
        self.id = str(uuid.uuid4())
        self.strategy = strategy
        self.symbol = symbol
        self.config_dict = config

        self._kill = threading.Event()
        self._pause = threading.Event()
        self._config_lock = threading.Lock()
        self._thread = threading.Thread(target=self._run, daemon=True)

        self.running = True
        self.phase = HUNTING
        self.message = "Worker starting"
        
        self.hunt_current = 0
        self.hunt_total = int(EngineConfig(config).get("breakout.num_hunt_main", 2))
        self.session_open = False
        self.active_signal: Optional[dict] = None
        self.today = {"outcome": None, "net_gain": 0.0}

        self._engine = TwoHunters(config=config)

    def start(self):
        self._thread.start()

    def pause(self):
        self._pause.set()

    def resume(self):
        self._pause.clear()

    def kill(self):
        self._kill.set()

    def update_config(self, new_config: dict):
        with self._config_lock:
            self.config_dict.update(new_config)
            self.hunt_total = int(EngineConfig(self.config_dict).get("breakout.num_hunt_main", 2))
            self._engine = TwoHunters(config=self.config_dict)
        
        self._set(self.phase, "Runtime configuration updated")

    @property
    def key(self) -> str:
        return self.id

    def to_state(self) -> dict:
        with self._config_lock:
            current_config = self.config_dict.copy()
            
        return {
            "id": self.id,
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
            "config": current_config,
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

    def _now(self):
        rates = mt5.copy_rates_from_pos(self.symbol, mt5.TIMEFRAME_M1, 0, 1)
        epoch_time = rates[0]['time']
        _now = datetime.fromtimestamp(epoch_time)
    
        return _now

    def _run(self):
        self._day = self._now().date()
        logger.info("worker %s started", self.key)
        self._set(HUNTING, f"Hunting phase 0/{self.hunt_total}, looking for setup")
        active_sig_obj = None

        while not self._kill.is_set():
            try:
                if self._pause.is_set():
                    if self.phase != PAUSED:
                        self._set(PAUSED, "Paused by user")
                    time.sleep(POLL_SECONDS)
                    continue

                now = self._now()
                
                with self._config_lock:
                    cfg = EngineConfig(self.config_dict)
                    s_start_str = cfg.get("sessions.main.start")
                    s_end_str = cfg.get("sessions.main.end")
                    s_start = datetime.strptime(s_start_str, "%H:%M").time()
                    s_end = datetime.strptime(s_end_str, "%H:%M").time()

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
                        self._set(MBOX_STILL_FORMING, "Waiting for session window")
                        time.sleep(POLL_SECONDS)
                        continue

                    with self._config_lock:
                        sig = self._engine.prepare_day(self.symbol, now)

                        reached = getattr(self._engine.breakout_engine, 'current_hunt', 0)
                        self.hunt_current = min(reached, self.hunt_total)

                    self._set(HUNTING, f"Hunting phase {self.hunt_current}/{self.hunt_total}")
                        
                    if sig is None:
                        time.sleep(POLL_SECONDS)
                        continue

                    active_sig_obj = sig
                    self.active_signal = self._sig_payload(sig)
                    self._place_order(sig)

                    if sig.is_order:
                        self._set(ORDER_PLACED, f"Setup found, {sig.action.value} order placed")
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

        # Skip if the order failed to generate a ticket
        if not getattr(sig, 'ticket', None):
            self._set(MONITORING, "Waiting for order ticket...")
            return

        # 1. Check if it is currently an ACTIVE POSITION
        positions = mt5.positions_get(ticket=sig.ticket)
        if positions is None:
            # MT5 connection error or busy, skip this tick to prevent false-closes
            return 
            
        if len(positions) > 0:
            pos = positions[0]
            # Calculate true floating net profit (profit + commission + swap)
            gain = pos.profit + getattr(pos, 'commission', 0.0) + getattr(pos, 'swap', 0.0)
            
            sig.gain = gain
            self.active_signal = self._sig_payload(sig)
            return

        # 2. Check if it is still a PENDING ORDER
        orders = mt5.orders_get(ticket=sig.ticket)
        if orders is None:
            return
            
        if len(orders) > 0:
            sig.gain = 0.0
            self.active_signal = self._sig_payload(sig)
            self._set(MONITORING, "Pending order active, waiting for execution...")
            return

        # 3. If neither active nor pending, it HAS CLOSED (hit TP/SL or user closed it)
        # We query the history deals linked to the initial position ticket
        deals = mt5.history_deals_get(position=sig.ticket)
        if deals is None:
            return
            
        if len(deals) > 0:
            # Calculate final realized net profit across all deals for this position
            final_gain = sum(d.profit + getattr(d, 'commission', 0.0) + getattr(d, 'swap', 0.0) for d in deals)
            outcome = "win" if final_gain >= 0 else "loss"
            
            self.today = {"outcome": outcome, "net_gain": self.today["net_gain"] + final_gain}
            self.active_signal = None
            self._set(DONE, f"Signal closed {outcome.upper()} {'+' if final_gain >= 0 else '-'}${abs(final_gain):.2f} - done for today")
        else:
            # 4. Fallback: Pending order was cancelled manually before it ever triggered
            self.active_signal = None
            self._set(DONE, "Order cancelled before execution - done for today")

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
            
            # Prevent duplicate consecutive logs from flooding the home screen
            if getattr(self, "_last_log_msg", None) != message:
                self._last_log_msg = message
                WorkerManager.instance().add_log(self.symbol, message)

class WorkerManager:
    _instance: Optional["WorkerManager"] = None
    _lock = threading.Lock()

    def __init__(self):
        self._workers: Dict[str, Worker] = {}
        # Stores the latest 50 system logs
        self.system_logs: deque = deque(maxlen=50)

    @classmethod
    def instance(cls) -> "WorkerManager":
        with cls._lock:
            if cls._instance is None:
                cls._instance = WorkerManager()
        return cls._instance

    def add_log(self, symbol: str, msg: str):
        """Adds a timestamped log to the queue."""
        ts = datetime.now().strftime("%H:%M")
        self.system_logs.appendleft({
            "timestamp": ts,
            "symbol": symbol,
            "message": msg
        })

    def get_logs(self) -> List[dict]:
        """Returns the recent logs in order (newest first)."""
        return list(self.system_logs)

    def start(self, symbol: str, config: Dict[str, Any], strategy: str = "TwoHunters") -> dict:
        worker = Worker(strategy, symbol, config)
        self._workers[worker.key] = worker
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
        return state

    def update_config(self, key: str, new_config: dict) -> Optional[dict]:
        w = self._workers.get(key)
        if not w:
            return None
        w.update_config(new_config)
        return w.to_state()

    def get_worker_state(self, key: str) -> Optional[dict]:
        w = self._workers.get(key)
        if not w:
            return None
        return w.to_state()

    def snapshot(self) -> List[dict]:
        return [w.to_state() for w in self._workers.values()]