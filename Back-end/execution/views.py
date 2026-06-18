from datetime import datetime, timedelta
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from .serializers import OrderSerializer
from marketdata.services.mt5_service import MT5Service

class ExecuteOrderView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = OrderSerializer(data=request.data)
        if serializer.is_valid():
            data = serializer.validated_data
            try:
                service = MT5Service()

                result = service.order_send(
                    symbol=data['symbol'],
                    volume=data['volume'],
                    side=data['order_type'],
                    price=data.get('price'),
                    sl=data.get('sl'),
                    tp=data.get('tp')
                )
                return Response({"status": "success", "data": result})
            except Exception as e:
                return Response({"error": str(e)}, status=400)
        return Response(serializer.errors, status=400)


class TradingDataView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        symbol = request.query_params.get("symbol")
        
        if not symbol:
            return Response({"error": "symbol param is required"}, status=400)
            
        try:
            service = MT5Service()
            # No date parameters passed from the client
            data = service.get_trading_data(symbol)
            return Response(data, status=200)
        except Exception as e:
            return Response({"error": str(e)}, status=500)