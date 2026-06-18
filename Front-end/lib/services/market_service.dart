import 'package:dio/dio.dart';

import '../models/candle.dart';
import 'api_client.dart';

class MarketService {
  Future<List<Candle>> getCandles({
    required String symbol,
    required String timeframe,
    int count = 100,
    DateTime? before,
  }) async {
    try {
      final response = await ApiClient.dio.get(
        "/marketdata/candles/",
        queryParameters: {
          "symbol": symbol,

          "timeframe": timeframe,

          "count": count,

          if (before != null) "before": before.toIso8601String(),
        },
      );

      final List data = response.data["data"];

      return data.map((e) => Candle.fromJson(e)).toList();
    } on DioException catch (e) {
      throw Exception(e.response?.data ?? e.message);
    }
  }
}
