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
                    "currency": account.currency
                }
            return None

    def get_trading_data(self, symbol):
        # 1. Fetch Open Positions (No dates needed)
        positions_raw = mt5.positions_get(symbol=symbol)
        positions = [p._asdict() | {'type_str': 'buy' if p.type == mt5.POSITION_TYPE_BUY else 'sell'} 
                    for p in (positions_raw or [])]

        # 2. Fetch Pending Orders (No dates needed)
        orders_raw = mt5.orders_get(symbol=symbol)
        orders = []
        if orders_raw is not None:
            for o in orders_raw:
                o_dict = o._asdict()
                type_map = {
                    mt5.ORDER_TYPE_BUY_LIMIT: 'buy_limit',
                    mt5.ORDER_TYPE_SELL_LIMIT: 'sell_limit',
                    mt5.ORDER_TYPE_BUY_STOP: 'buy_stop',
                    mt5.ORDER_TYPE_SELL_STOP: 'sell_stop',
                }
                if o.type in type_map:
                    o_dict['type_str'] = type_map[o.type]
                    orders.append(o_dict)

        # 3. Fetch Deals (Internal 30-day range)
        end_date = datetime.now() + timedelta(days=1)
        start_date = end_date - timedelta(days=365)
        
        deals_raw = mt5.history_deals_get(start_date, end_date)
        deals = []
        if deals_raw is not None:
            for d in deals_raw:
                # Filter by symbol manually to avoid API group issues
                if d.symbol == symbol:
                    d_dict = d._asdict()
                    d_dict['type_str'] = 'buy' if d.type == mt5.DEAL_TYPE_BUY else 'sell'
                    d_dict['entry_str'] = 'in' if d.entry == mt5.DEAL_ENTRY_IN else ('out' if d.entry == mt5.DEAL_ENTRY_OUT else 'inout')
                    deals.append(d_dict)

        return {
            "positions": positions,
            "orders": orders,
            "deals": deals
        }

    def order_send(self, symbol, volume, side, price=None, sl=None, tp=None, magic=123456):
        # 1. Ensure SL, TP, and Volume are properly typed
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

        # 2. Determine Action, Order Type, and Price based on Market vs Pending Orders
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
                
            if side_lower == 'buy':
                order_type = mt5.ORDER_TYPE_BUY
                price = tick.ask if price is None else price
            elif side_lower == 'sell':
                order_type = mt5.ORDER_TYPE_SELL
                price = tick.bid if price is None else price
            else:
                raise ValueError("Market side must be 'buy' or 'sell'")

        # 3. Construct the base request template
        request = {
            "action": action_type,
            "symbol": symbol,
            "volume": float(volume),
            "type": order_type,
            "price": float(price),
            "sl": float(sl),
            "tp": float(tp),
            "deviation": 20,  # Slippage tolerance
            "magic": magic,
            "comment": "API Order",
            "type_time": mt5.ORDER_TIME_GTC,
        }

        # 4. Execution filling retry guard (Try IOC, fallback to FOK if it fails)
        filling_modes = [mt5.ORDER_FILLING_IOC, mt5.ORDER_FILLING_FOK]
        last_result = None

        for filling_mode in filling_modes:
            request["type_filling"] = filling_mode
            last_result = mt5.order_send(request)

            if last_result is not None and last_result.retcode == mt5.TRADE_RETCODE_DONE:
                return last_result
            
            # Optional trace debug logging
            print(f"Order failed with filling type {filling_mode}. Retrying with next mode if available...")

        # 5. If it exits the loop, both filling attempts failed
        if last_result is None:
            raise Exception("Order execution failed: Internal MT5 error or request parameters were structured incorrectly.")
        
        raise Exception(f"Order failed: {last_result.comment} (Code: {last_result.retcode})")

    def get_candles(self, symbol, timeframe, count=500, before=None):
        if timeframe not in TIMEFRAME_MAP:
            raise ValueError("Invalid timeframe")

        if before:
            before_dt = datetime.fromisoformat(before.replace("Z", "+00:00"))
            before_dt = before_dt - timedelta(seconds=1)

            rates = mt5.copy_rates_from(
                symbol, 
                TIMEFRAME_MAP[timeframe], 
                before_dt, 
                count
            )
        else:
            rates = mt5.copy_rates_from_pos(
                symbol, 
                TIMEFRAME_MAP[timeframe], 
                0, 
                count
            )

        if rates is None:
            return []

        candles = []
        for candle in rates:
            candles.append({
                "time": datetime.fromtimestamp(
                    candle["time"], tz=timezone.utc
                ).isoformat(),
                "open": float(candle["open"]),
                "high": float(candle["high"]),
                "low": float(candle["low"]),
                "close": float(candle["close"]),
                "volume": int(candle["tick_volume"])
            })

        return candles