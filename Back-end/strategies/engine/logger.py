"""
Lightweight logging shim.

The original DIO engine used a heavy `TradingLogger` plus `log_signal_event` /
`log_system_event` helpers that wrote to many rotating files. For the Django
integration we only need plain stdlib logging, so this module provides the same
call surface the ported engine expects, backed by `logging`.
"""
from __future__ import annotations
import logging

_LOGGER = logging.getLogger("strategies.engine")


class TradingLogger:
    """Compatibility shim. All getters return the same module logger."""

    @staticmethod
    def get_main_logger() -> logging.Logger:
        return _LOGGER

    @staticmethod
    def get_trading_logger() -> logging.Logger:
        return _LOGGER

    @staticmethod
    def get_backtest_logger() -> logging.Logger:
        return _LOGGER


def log_signal_event(event: str, symbol: str = "", action: str = "", **kwargs) -> None:
    _LOGGER.debug("signal_event=%s symbol=%s action=%s %s", event, symbol, action, kwargs)


def log_system_event(event: str, **kwargs) -> None:
    _LOGGER.debug("system_event=%s %s", event, kwargs)
