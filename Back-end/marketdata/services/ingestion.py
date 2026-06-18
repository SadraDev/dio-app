from ..models import Candle
from .mt5_service import MT5Service


class CandleIngestor:
    @staticmethod
    def sync(symbol, timeframe, count=500):
        service = MT5Service()
        candles = service.get_candles(symbol, timeframe, count)

        for c in candles:
            Candle.objects.update_or_create(
                symbol=symbol,
                timeframe=timeframe,
                time=c["time"],
                defaults={
                    "open": c["open"],
                    "high": c["high"],
                    "low": c["low"],
                    "close": c["close"],
                    "volume": c.get("volume", 0),
                }
            )