from rest_framework import serializers
from .models import StrategyConfig, BacktestRun


class StrategyConfigSerializer(serializers.ModelSerializer):
    class Meta:
        model = StrategyConfig
        fields = ["name", "config", "updated_at"]
        read_only_fields = ["name", "updated_at"]


class StartProcessSerializer(serializers.Serializer):
    symbol = serializers.CharField()
    # When omitted, the worker uses the saved TwoHunters config.
    config = serializers.JSONField(required=False)
    dry_run = serializers.BooleanField(required=False, default=True)


class WorkerControlSerializer(serializers.Serializer):
    key = serializers.CharField()  # e.g. "TwoHunters::EURUSD"
    action = serializers.ChoiceField(choices=["pause", "resume", "kill"])


class BacktestRequestSerializer(serializers.Serializer):
    symbols = serializers.ListField(child=serializers.CharField(), allow_empty=False)
    start_date = serializers.DateField()
    end_date = serializers.DateField()
    config = serializers.JSONField(required=False)


class BacktestRunSerializer(serializers.ModelSerializer):
    class Meta:
        model = BacktestRun
        fields = ["id", "strategy_name", "symbols", "start_date", "end_date",
                  "status", "results", "error", "created_at"]
        read_only_fields = fields
