from django.urls import path
from .views import (
    StrategyListView,
    TwoHuntersConfigView,
    StartProcessView,
    WorkerControlView,
    RunningStrategiesView,
    BacktestView,
    BacktestDetailView,
)

urlpatterns = [
    path("", StrategyListView.as_view(), name="strategy-list"),

    # TwoHunters config (GET / PUT)
    path("twohunters/config/", TwoHuntersConfigView.as_view(), name="twohunters-config"),

    # Live workers
    path("twohunters/start/", StartProcessView.as_view(), name="twohunters-start"),
    path("workers/control/", WorkerControlView.as_view(), name="worker-control"),
    path("workers/", RunningStrategiesView.as_view(), name="worker-snapshot"),

    # Backtests
    path("twohunters/backtest/", BacktestView.as_view(), name="twohunters-backtest"),
    path("backtests/<int:pk>/", BacktestDetailView.as_view(), name="backtest-detail"),
]
