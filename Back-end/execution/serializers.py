from rest_framework import serializers


class OrderSerializer(serializers.Serializer):
    symbol = serializers.CharField()
    volume = serializers.FloatField()
    order_type = serializers.ChoiceField(
        choices=["buy", "sell", "buy_limit", "sell_limit"]
    )
    price = serializers.FloatField(required=False, allow_null=True)  # pending only
    sl = serializers.FloatField(required=False, allow_null=True)
    tp = serializers.FloatField(required=False, allow_null=True)


class ClosePositionSerializer(serializers.Serializer):
    ticket = serializers.IntegerField()
    volume = serializers.FloatField(required=False, allow_null=True)  # partial close


class ModifyPositionSerializer(serializers.Serializer):
    ticket = serializers.IntegerField()
    sl = serializers.FloatField(required=False, allow_null=True)
    tp = serializers.FloatField(required=False, allow_null=True)


class CancelOrderSerializer(serializers.Serializer):
    ticket = serializers.IntegerField()
