from django.db import models

from .engine.config import default_config


class StrategyConfig(models.Model):
    """
    Persisted, editable config for a strategy (e.g. "TwoHunters").

    The whole strategy config lives in a single JSON blob so the engine can be
    constructed straight from it. `get_or_create_default` seeds the trimmed
    TwoHunters config the first time it is requested.
    """
    name = models.CharField(max_length=64, unique=True)
    config = models.JSONField(default=dict)
    updated_at = models.DateTimeField(auto_now=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.name

    @classmethod
    def get_or_create_default(cls, name: str = "TwoHunters") -> "StrategyConfig":
        obj, created = cls.objects.get_or_create(
            name=name, defaults={"config": default_config()})
        return obj


class BacktestRun(models.Model):
    """A single backtest invocation and its results."""
    STATUS_CHOICES = [
        ("pending", "pending"),
        ("running", "running"),
        ("completed", "completed"),
        ("failed", "failed"),
    ]

    strategy_name = models.CharField(max_length=64, default="TwoHunters")
    symbols = models.JSONField(default=list)
    start_date = models.DateField()
    end_date = models.DateField()
    config = models.JSONField(default=dict)
    status = models.CharField(max_length=16, choices=STATUS_CHOICES, default="pending")
    results = models.JSONField(default=dict, blank=True)
    error = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"Backtest {self.strategy_name} {self.symbols} [{self.status}]"
