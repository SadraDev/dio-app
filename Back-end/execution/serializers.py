from rest_framework import serializers

class OrderSerializer(serializers.Serializer):
    symbol = serializers.CharField()
    volume = serializers.FloatField()
    order_type = serializers.ChoiceField(choices=['buy', 'sell', 'buy_limit', 'sell_limit'])
    price = serializers.FloatField(required=False, allow_null=True) # Only for pending orders
    sl = serializers.FloatField(required=False, allow_null=True)
    tp = serializers.FloatField(required=False, allow_null=True)