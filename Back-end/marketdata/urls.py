from django.urls import path
from .views import CandleDataView

urlpatterns=[
    path("candles/", CandleDataView.as_view())
]