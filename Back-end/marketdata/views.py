from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated

from .services.mt5_service import MT5Service

class AccountInfoView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        service = MT5Service()
        data = service.get_account_info()
        if data:
            return Response(data)
        return Response({"error": "Could not retrieve account info"}, status=404)

class CandleDataView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        symbol = request.GET.get("symbol")
        timeframe = request.GET.get("timeframe", "M1")
        count = int(request.GET.get("count", 100))
        before = request.GET.get("before")

        if not symbol:
            return Response({"error": "symbol required"}, status=400)

        try:
            service = MT5Service()

            candles = service.get_candles(
                symbol=symbol,
                timeframe=timeframe,
                count=count,
                before=before
            )

            return Response({
                "symbol": symbol,
                "timeframe": timeframe,
                "count": len(candles),
                "data": candles
            })

        except Exception as e:
            return Response({"error": str(e)}, status=500)