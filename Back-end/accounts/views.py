from rest_framework_simplejwt.tokens import RefreshToken
from django.contrib.auth.models import User
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.permissions import IsAuthenticated
from marketdata.services.mt5_service import MT5Service

class RegisterView(APIView):
    def post(self, request):
        username = request.data["username"]
        password = request.data["password"]

        user = User.objects.create_user(
            username=username,
            password=password
        )

        refresh = RefreshToken.for_user(user)

        return Response({
            "refresh": str(refresh),
            "access": str(refresh.access_token),
        })

class AccountInfoView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        service = MT5Service()
        data = service.get_account_info()
        if data:
            return Response(data)
        return Response({"error": "Could not retrieve account info"}, status=404)