from django.db import models


class Candle(models.Model):
    symbol = models.CharField(max_length=20, db_index=True)
    timeframe = models.CharField(max_length=10, db_index=True)

    time = models.DateTimeField(db_index=True)

    open = models.FloatField()
    high = models.FloatField()
    low = models.FloatField()
    close = models.FloatField()

    volume = models.FloatField(null=True, blank=True)

    class Meta:
        unique_together = ("symbol", "timeframe", "time")
        ordering = ["-time"]

    def __str__(self):
        return f"{self.symbol} {self.timeframe} {self.time}"