import asyncio
from .services.mt5_service import MT5Service

service = MT5Service()

async def run_tick_loop():
    while True:
        try:
            service.push_latest_candle("EURUSD")
        except Exception as e:
            print("tick error:", e)

        await asyncio.sleep(2)