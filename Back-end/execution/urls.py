from django.urls import path
from .views import ExecuteOrderView, TradingDataView

urlpatterns = [
    path('order/', ExecuteOrderView.as_view(), name='execute-order'),
    path('trading-data/', TradingDataView.as_view(), name='trading-data'),
]