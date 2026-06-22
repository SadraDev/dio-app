from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated

from .serializers import (
    OrderSerializer,
    ClosePositionSerializer,
    ModifyPositionSerializer,
    CancelOrderSerializer,
)
from marketdata.services.mt5_service import MT5Service


def _result_to_dict(result):
    """MT5 result objects aren't JSON-serializable; pull the useful fields."""
    if result is None:
        return None
    try:
        return {
            "retcode": result.retcode,
            "order": getattr(result, "order", None),
            "deal": getattr(result, "deal", None),
            "volume": getattr(result, "volume", None),
            "price": getattr(result, "price", None),
            "comment": getattr(result, "comment", None),
        }
    except Exception:
        return {"raw": str(result)}


class ExecuteOrderView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = OrderSerializer(data=request.data)
        if serializer.is_valid():
            data = serializer.validated_data
            try:
                service = MT5Service()
                result = service.order_send(
                    symbol=data["symbol"],
                    volume=data["volume"],
                    side=data["order_type"],
                    price=data.get("price"),
                    sl=data.get("sl"),
                    tp=data.get("tp"),
                )
                return Response({"status": "success", "data": _result_to_dict(result)})
            except Exception as e:
                return Response({"error": str(e)}, status=400)
        return Response(serializer.errors, status=400)


class ClosePositionView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = ClosePositionSerializer(data=request.data)
        if serializer.is_valid():
            data = serializer.validated_data
            try:
                service = MT5Service()
                result = service.close_position(
                    ticket=data["ticket"],
                    volume=data.get("volume"),
                )
                return Response({"status": "success", "data": _result_to_dict(result)})
            except Exception as e:
                return Response({"error": str(e)}, status=400)
        return Response(serializer.errors, status=400)


class ModifyPositionView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = ModifyPositionSerializer(data=request.data)
        if serializer.is_valid():
            data = serializer.validated_data
            try:
                service = MT5Service()
                result = service.modify_position(
                    ticket=data["ticket"],
                    sl=data.get("sl"),
                    tp=data.get("tp"),
                )
                return Response({"status": "success", "data": _result_to_dict(result)})
            except Exception as e:
                return Response({"error": str(e)}, status=400)
        return Response(serializer.errors, status=400)


class CancelOrderView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = CancelOrderSerializer(data=request.data)
        if serializer.is_valid():
            data = serializer.validated_data
            try:
                service = MT5Service()
                result = service.cancel_order(ticket=data["ticket"])
                return Response({"status": "success", "data": _result_to_dict(result)})
            except Exception as e:
                return Response({"error": str(e)}, status=400)
        return Response(serializer.errors, status=400)


class TradingDataView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        symbol = request.query_params.get("symbol")
        
        try:
            service = MT5Service()
            data = service.get_trading_data(symbol)
            return Response(data, status=200)
        except Exception as e:
            return Response({"error": str(e)}, status=500)
