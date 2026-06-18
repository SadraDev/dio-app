from django.contrib import admin
from django.urls import path
from accounts.views import RegisterView
from django.urls import include

from rest_framework_simplejwt.views import (
    TokenObtainPairView,
    TokenRefreshView,
)

urlpatterns = [
    path('admin/', admin.site.urls),

    path('api/auth/register/', RegisterView.as_view()),
    path('api/auth/login/', TokenObtainPairView.as_view()),
    path('api/auth/refresh/', TokenRefreshView.as_view()),
    path("api/marketdata/", include("marketdata.urls")),
    path('api/execution/', include('execution.urls')),
    path('api/accounts/', include('accounts.urls')),
]