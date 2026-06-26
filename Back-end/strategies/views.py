from datetime import datetime

from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated

from .models import StrategyConfig, BacktestRun
from .serializers import (
    StrategyConfigSerializer, StartProcessSerializer, WorkerControlSerializer,
    BacktestRequestSerializer, BacktestRunSerializer,
)
from .manager import WorkerManager
from .engine.strategies.two_hunters import TwoHunters


# ── Strategy catalog ─────────────────────────────────────────────────────────
class StrategyListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response({
            "strategies": [
                {"name": "TwoHunters", "implemented": True,
                 "description": "MBox breakout hunter (default breakout)."},
                {"name": "Tweny", "implemented": False,
                 "description": "Not yet wired to the backend."},
            ]
        })


# ── TwoHunters config (edit) ─────────────────────────────────────────────────
class TwoHuntersConfigView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        obj = StrategyConfig.get_or_create_default("TwoHunters")
        return Response(StrategyConfigSerializer(obj).data)

    def put(self, request):
        obj = StrategyConfig.get_or_create_default("TwoHunters")
        new_config = request.data.get("config")
        if not isinstance(new_config, dict):
            return Response({"error": "config must be an object"}, status=400)
        obj.config = new_config
        obj.save(update_fields=["config", "updated_at"])
        return Response(StrategyConfigSerializer(obj).data)


# ── Live workers: start / control / update / snapshot ────────────────────────
class StartProcessView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        ser = StartProcessSerializer(data=request.data)
        if not ser.is_valid():
            return Response(ser.errors, status=400)
        data = ser.validated_data
        config = data.get("config")
        if config is None:
            config = StrategyConfig.get_or_create_default("TwoHunters").config
        state = WorkerManager.instance().start(
            symbol=data["symbol"], config=config)
        return Response(state)


class WorkerControlView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        ser = WorkerControlSerializer(data=request.data)
        if not ser.is_valid():
            return Response(ser.errors, status=400)
        mgr = WorkerManager.instance()
        action = ser.validated_data["action"]
        key = ser.validated_data["key"]
        state = getattr(mgr, action)(key)
        if state is None:
            return Response({"error": f"worker '{key}' not found"}, status=404)
        return Response(state)


class WorkerUpdateConfigView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        worker_id = request.data.get("id")
        new_config = request.data.get("config")

        if not worker_id or not isinstance(new_config, dict):
            return Response({"error": "Invalid payload. 'id' and 'config' (dict) are required."}, status=400)

        mgr = WorkerManager.instance()
        state = mgr.update_config(worker_id, new_config)

        if state is None:
            return Response({"error": f"worker '{worker_id}' not found"}, status=404)

        return Response(state)


class RunningStrategiesView(APIView):
    """Gets the snapshot of ALL running workers AND recent system logs."""
    permission_classes = [IsAuthenticated]

    def get(self, request):
        mgr = WorkerManager.instance()
        return Response({
            "workers": mgr.snapshot(),
            "logs": mgr.get_logs()
        })


class WorkerStateView(APIView):
    """Gets the live state of ONE specific worker by its UUID."""
    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        state = WorkerManager.instance().get_worker_state(pk)
        if not state:
            return Response({"error": "Worker not found"}, status=404)
        return Response(state)


# ── Backtests ────────────────────────────────────────────────────────────────
import threading

def run_backtest_async(run_id):
    from .models import BacktestRun
    from .engine.strategies.two_hunters import TwoHunters
    import traceback
    
    try:
        run = BacktestRun.objects.get(id=run_id)
        engine = TwoHunters(config=run.config)
        
        # Convert Dates to Datetimes for the engine
        sd = datetime.combine(run.start_date, datetime.min.time())
        ed = datetime.combine(run.end_date, datetime.min.time())
        
        results = engine.backtest(symbols=run.symbols, start_date=sd, end_date=ed)
        
        run.results = results
        run.status = "completed"
        run.save(update_fields=["results", "status"])
    except Exception:
        run = BacktestRun.objects.get(id=run_id)
        run.error = traceback.format_exc()
        run.status = "failed"
        run.save(update_fields=["error", "status"])


class BacktestView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        ser = BacktestRequestSerializer(data=request.data)
        if not ser.is_valid():
            return Response(ser.errors, status=400)
        
        data = ser.validated_data
        config = data.get("config") or StrategyConfig.get_or_create_default("TwoHunters").config

        run = BacktestRun.objects.create(
            strategy_name="TwoHunters", 
            symbols=data["symbols"],
            start_date=data["start_date"], 
            end_date=data["end_date"],
            config=config, 
            status="running",
        )

        # ── Start the backtest in the background ──
        thread = threading.Thread(target=run_backtest_async, args=(run.id,))
        thread.start()

        # Immediately return the 'running' status so the frontend can start polling
        return Response(BacktestRunSerializer(run).data, status=200)

    def get(self, request):
        runs = BacktestRun.objects.all()[:25]
        return Response({"runs": BacktestRunSerializer(runs, many=True).data})


class BacktestDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        try:
            run = BacktestRun.objects.get(id=pk)
        except BacktestRun.DoesNotExist:
            return Response({"error": "not found"}, status=404)
        return Response(BacktestRunSerializer(run).data)