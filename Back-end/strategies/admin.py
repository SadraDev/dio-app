from django.contrib import admin
from .models import StrategyConfig, BacktestRun


@admin.register(StrategyConfig)
class StrategyConfigAdmin(admin.ModelAdmin):
    list_display = ("name", "updated_at")


@admin.register(BacktestRun)
class BacktestRunAdmin(admin.ModelAdmin):
    list_display = ("id", "strategy_name", "status", "created_at")
    list_filter = ("status", "strategy_name")
