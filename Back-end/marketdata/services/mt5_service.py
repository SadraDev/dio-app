import MetaTrader5 as mt5
from datetime import datetime, timezone, timedelta

TIMEFRAME_MAP = {
    "M1": mt5.TIMEFRAME_M1,
    "M5": mt5.TIMEFRAME_M5,
    "M15": mt5.TIMEFRAME_M15,
    "M30": mt5.TIMEFRAME_M30,
    "H1": mt5.TIMEFRAME_H1,
    "H4": mt5.TIMEFRAME_H4,
    "D1": mt5.TIMEFRAME_D1,
    "W1": mt5.TIMEFRAME_W1,
    "MN1": mt5.TIMEFRAME_MN1,
}


class MT5Service:
    def __init__(self):
        connected = mt5.initialize()
        if not connected:
            raise Exception("MT5 initialization failed")

    def get_account_info(self):
        account = mt5.account_info()
        if account:
            return {
                "balance": account.balance,
                "equity": account.equity,
                "margin": account.margin,
                "free_margin": account.margin_free,
                "margin_level": account.margin_level,
                "currency": account.currency,
                "leverage": account.leverage,
            }
        return None

    def get_trading_data(self, symbol=None):
        # 1. Open Positions
        # If symbol is provided, fetch for that symbol. Otherwise, fetch all.
        if symbol:
            positions_raw = mt5.positions_get(symbol=symbol)
        else:
            positions_raw = mt5.positions_get()
            
        positions = [
            p._asdict() | {"type_str": "buy" if p.type == mt5.POSITION_TYPE_BUY else "sell"}
            for p in (positions_raw or [])
        ]

        # 2. Pending Orders
        if symbol:
            orders_raw = mt5.orders_get(symbol=symbol)
        else:
            orders_raw = mt5.orders_get()
            
        orders = []
        if orders_raw is not None:
            for o in orders_raw:
                o_dict = o._asdict()
                type_map = {
                    mt5.ORDER_TYPE_BUY_LIMIT: "buy_limit",
                    mt5.ORDER_TYPE_SELL_LIMIT: "sell_limit",
                    mt5.ORDER_TYPE_BUY_STOP: "buy_stop",
                    mt5.ORDER_TYPE_SELL_STOP: "sell_stop",
                }
                if o.type in type_map:
                    o_dict["type_str"] = type_map[o.type]
                    orders.append(o_dict)

        # 3. Deals (internal 365-day range)
        end_date = datetime.now() + timedelta(days=1)
        start_date = end_date - timedelta(days=365)

        # history_deals_get automatically gets all deals in the time range
        deals_raw = mt5.history_deals_get(start_date, end_date)
        deals = []
        if deals_raw is not None:
            for d in deals_raw:
                # If symbol is None, it ignores the symbol check and just checks price > 0
                if (not symbol or d.symbol == symbol) and d.price > 0:
                    d_dict = d._asdict()
                    d_dict["type_str"] = "buy" if d.type == mt5.DEAL_TYPE_BUY else "sell"
                    d_dict["entry_str"] = (
                        "in"
                        if d.entry == mt5.DEAL_ENTRY_IN
                        else ("out" if d.entry == mt5.DEAL_ENTRY_OUT else "inout")
                    )
                    deals.append(d_dict)

        return {"positions": positions, "orders": orders, "deals": deals}

    # ──────────────────────────────────────────────────────────────────
    # internal: send a request, retrying IOC then FOK filling modes
    # ──────────────────────────────────────────────────────────────────
    def _send_with_filling(self, request, error_label="Order"):
        filling_modes = [mt5.ORDER_FILLING_FOK, mt5.ORDER_FILLING_IOC]
        last_result = None
        for filling_mode in filling_modes:
            request["type_filling"] = filling_mode
            last_result = mt5.order_send(request)
            if last_result is not None and last_result.retcode == mt5.TRADE_RETCODE_DONE:
                return last_result
        if last_result is None:
            raise Exception(f"{error_label} failed: internal MT5 error or bad request.")
        raise Exception(f"{error_label} failed: {last_result.comment} (Code: {last_result.retcode})")

    def order_send(self, symbol, volume, side, price=None, sl=None, tp=None, magic=123456):
        sl = float(sl or 0.0)
        tp = float(tp or 0.0)
        volume = float(volume)

        symbol_info = mt5.symbol_info(symbol)
        if symbol_info is None:
            raise Exception(f"Symbol {symbol} not found")

        if not symbol_info.visible:
            if not mt5.symbol_select(symbol, True):
                raise Exception(f"Symbol {symbol} is not visible and could not be selected")

        side_lower = side.lower()

        if "_limit" in side_lower:
            action_type = mt5.TRADE_ACTION_PENDING
            if price is None:
                raise ValueError("Price must be specified for limit orders")
            if side_lower == "buy_limit":
                order_type = mt5.ORDER_TYPE_BUY_LIMIT
            elif side_lower == "sell_limit":
                order_type = mt5.ORDER_TYPE_SELL_LIMIT
            else:
                raise ValueError(f"Unsupported limit order side: {side}")
        else:
            action_type = mt5.TRADE_ACTION_DEAL
            tick = mt5.symbol_info_tick(symbol)
            if tick is None:
                raise Exception(f"Could not retrieve tick data for {symbol}")
            if side_lower == "buy":
                order_type = mt5.ORDER_TYPE_BUY
                price = tick.ask if price is None else price
            elif side_lower == "sell":
                order_type = mt5.ORDER_TYPE_SELL
                price = tick.bid if price is None else price
            else:
                raise ValueError("Market side must be 'buy' or 'sell'")

        request = {
            "action": action_type,
            "symbol": symbol,
            "volume": float(volume),
            "type": order_type,
            "price": float(price),
            # "sl": float(sl),
            # "tp": float(tp),
            "deviation": 20,
            "magic": magic,
            "comment": "API Order",
            "type_time": mt5.ORDER_TIME_GTC,
        }
        return self._send_with_filling(request, error_label="Order")

    # ──────────────────────────────────────────────────────────────────
    # NEW: close an open position by ticket (market close, opposite side)
    # ──────────────────────────────────────────────────────────────────
    def close_position(self, ticket, volume=None, magic=123456):
        positions = mt5.positions_get(ticket=int(ticket))
        if not positions:
            raise Exception(f"Position {ticket} not found")
        pos = positions[0]

        tick = mt5.symbol_info_tick(pos.symbol)
        if tick is None:
            raise Exception(f"Could not retrieve tick data for {pos.symbol}")

        if pos.type == mt5.POSITION_TYPE_BUY:
            order_type = mt5.ORDER_TYPE_SELL
            price = tick.bid
        else:
            order_type = mt5.ORDER_TYPE_BUY
            price = tick.ask

        close_volume = float(volume) if volume else float(pos.volume)

        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": pos.symbol,
            "position": int(ticket),
            "volume": close_volume,
            "type": order_type,
            "price": float(price),
            "deviation": 20,
            "magic": magic,
            "comment": "API Close",
            "type_time": mt5.ORDER_TIME_GTC,
        }
        return self._send_with_filling(request, error_label="Close")

    # ──────────────────────────────────────────────────────────────────
    # NEW: modify SL / TP of an open position
    # ──────────────────────────────────────────────────────────────────
    def modify_position(self, ticket, sl=None, tp=None):
        positions = mt5.positions_get(ticket=int(ticket))
        if not positions:
            raise Exception(f"Position {ticket} not found")
        pos = positions[0]

        new_sl = float(sl) if sl is not None else float(pos.sl)
        new_tp = float(tp) if tp is not None else float(pos.tp)

        request = {
            "action": mt5.TRADE_ACTION_SLTP,
            "symbol": pos.symbol,
            "position": int(ticket),
            "sl": new_sl,
            "tp": new_tp,
        }
        result = mt5.order_send(request)
        if result is None or result.retcode != mt5.TRADE_RETCODE_DONE:
            comment = result.comment if result else "internal MT5 error"
            code = result.retcode if result else "N/A"
            raise Exception(f"Modify failed: {comment} (Code: {code})")
        return result

    # ──────────────────────────────────────────────────────────────────
    # NEW: cancel a pending order by ticket
    # ──────────────────────────────────────────────────────────────────
    def cancel_order(self, ticket):
        request = {
            "action": mt5.TRADE_ACTION_REMOVE,
            "order": int(ticket),
        }
        result = mt5.order_send(request)
        if result is None or result.retcode != mt5.TRADE_RETCODE_DONE:
            comment = result.comment if result else "internal MT5 error"
            code = result.retcode if result else "N/A"
            raise Exception(f"Cancel failed: {comment} (Code: {code})")
        return result

    def get_candles(self, symbol, timeframe, count=500, before=None):
        if timeframe not in TIMEFRAME_MAP:
            raise ValueError("Invalid timeframe")

        if before:
            before_dt = datetime.fromisoformat(before.replace("Z", "+00:00"))
            before_dt = before_dt - timedelta(seconds=1)
            rates = mt5.copy_rates_from(symbol, TIMEFRAME_MAP[timeframe], before_dt, count)
        else:
            rates = mt5.copy_rates_from_pos(symbol, TIMEFRAME_MAP[timeframe], 0, count)

        if rates is None:
            return []

        candles = []
        for candle in rates:
            # Guard against malformed bars (missing/zero OHLC) that would
            # otherwise distort the chart's price axis.
            if candle["open"] <= 0 or candle["high"] <= 0 or candle["low"] <= 0 or candle["close"] <= 0:
                continue
            candles.append({
                "time": datetime.fromtimestamp(candle["time"], tz=timezone.utc).isoformat(),
                "open": float(candle["open"]),
                "high": float(candle["high"]),
                "low": float(candle["low"]),
                "close": float(candle["close"]),
                "volume": int(candle["tick_volume"]),
            })
        return candles
