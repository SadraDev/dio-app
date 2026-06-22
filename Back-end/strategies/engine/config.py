"""
Engine configuration.

The original DIO project used a global YAML-backed singleton (`config.settings`).
That is unsafe here because several TwoHunters workers run concurrently in the
same Django process, each with its OWN config. So instead every engine object
receives an `EngineConfig` instance and reads values through `.get("dotted.path")`,
exactly like the old `settings.get(...)` API -- but scoped per worker.

DEFAULT_TWO_HUNTERS_CONFIG is the trimmed config requested:
  * no `choch` section, no `live_trading` section
  * `flags` keeps ONLY `order_block_significance`
  * a top-level `risk_percent` was added
"""
from __future__ import annotations
import copy
from typing import Any, Dict


# --- Default config for the TwoHunters strategy (trimmed) --------------------
DEFAULT_TWO_HUNTERS_CONFIG: Dict[str, Any] = {
    "risk_percent": 0.005,          # <-- added: fraction of balance risked per trade
    "account": {
        "balance": 2000,
    },
    "commission": 0.0,
    "min_lot_size": 0.01,
    "max_risk_percent": 0.05,
    "margin_pips": 0.1,             # in pips
    "fvg": {
        "min_size_pips": 5.0,
        "max_size_pips": 10.0,
    },
    "ratios": {
        "stop_loss": 1.0,
        "take_profit": 2.0,
    },
    "breakout": {
        "num_hunt_main": 2,
    },
    "mbox_time": {
        "start": "04:30",
        "end": "12:29",
    },
    "sessions": {
        "main": {"start": "12:30", "end": "22:00"},
        "london": {"start": "13:30", "end": "17:29"},
        "newyork": {"start": "18:30", "end": "00:29"},
    },
    "flags": {
        # CHoCH flags + live_trading removed; ONLY this one is kept.
        "order_block_significance": 0.02,
    },
}


def default_config() -> Dict[str, Any]:
    """Return a fresh deep copy of the default TwoHunters config."""
    return copy.deepcopy(DEFAULT_TWO_HUNTERS_CONFIG)


class EngineConfig:
    """
    Thin wrapper around a plain dict that supports dotted-path lookups.

    The dotted paths are RELATIVE to the strategy config, e.g.:
        cfg.get("breakout.num_hunt_main")
        cfg.get("flags.order_block_significance")
        cfg.get("sessions.main.start")
    """

    def __init__(self, data: Dict[str, Any] | None = None):
        self._d: Dict[str, Any] = data if data is not None else default_config()

    def get(self, key_path: str, default: Any = None) -> Any:
        node: Any = self._d
        for key in key_path.split("."):
            if isinstance(node, dict) and key in node:
                node = node[key]
            else:
                return default
        return node

    def set(self, key_path: str, value: Any) -> None:
        keys = key_path.split(".")
        node = self._d
        for key in keys[:-1]:
            node = node.setdefault(key, {})
        node[keys[-1]] = value

    def as_dict(self) -> Dict[str, Any]:
        return copy.deepcopy(self._d)
