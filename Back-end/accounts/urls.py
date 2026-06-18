from django.urls import path
from .views import AccountInfoView

urlpatterns = [
    path('info/', AccountInfoView.as_view(), name='account-info'),
]