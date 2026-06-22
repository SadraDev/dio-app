from django.urls import path
from .views import (
    ExecuteOrderView,
    ClosePositionView,
    ModifyPositionView,
    CancelOrderView,
    TradingDataView,
)

urlpatterns = [
    path("order/", ExecuteOrderView.as_view(), name="execute-order"),
    path("order/cancel/", CancelOrderView.as_view(), name="cancel-order"),
    path("position/close/", ClosePositionView.as_view(), name="close-position"),
    path("position/modify/", ModifyPositionView.as_view(), name="modify-position"),
    path("trading-data/", TradingDataView.as_view(), name="trading-data"),
]
