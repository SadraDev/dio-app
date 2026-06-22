import '../models/trading_data.dart';
import 'api_client.dart';

/// Thin wrapper over the execution + trading-data endpoints so both chart
/// screens share one place that talks to the backend (no dummy data).
class TradeService {
  /// Market order. side = 'buy' | 'sell'. sl/tp are absolute prices (optional).
  static Future<dynamic> openMarket({
    required String symbol,
    required double volume,
    required String side,
    double? sl,
    double? tp,
  }) {
    return ApiClient.post('/execution/order/', body: {
      "symbol": symbol,
      "volume": volume,
      "order_type": side,
      if (sl != null) "sl": sl,
      if (tp != null) "tp": tp,
    });
  }

  /// Pending limit order. side = 'buy_limit' | 'sell_limit'.
  static Future<dynamic> placePending({
    required String symbol,
    required double volume,
    required String side,
    required double price,
    double? sl,
    double? tp,
  }) {
    return ApiClient.post('/execution/order/', body: {
      "symbol": symbol,
      "volume": volume,
      "order_type": side,
      "price": price,
      if (sl != null) "sl": sl,
      if (tp != null) "tp": tp,
    });
  }

  static Future<dynamic> closePosition(int ticket, {double? volume}) {
    return ApiClient.post('/execution/position/close/', body: {
      "ticket": ticket,
      if (volume != null) "volume": volume,
    });
  }

  static Future<dynamic> modifyPosition(int ticket, {double? sl, double? tp}) {
    return ApiClient.post('/execution/position/modify/', body: {
      "ticket": ticket,
      if (sl != null) "sl": sl,
      if (tp != null) "tp": tp,
    });
  }

  static Future<dynamic> cancelOrder(int ticket) {
    return ApiClient.post('/execution/order/cancel/', body: {"ticket": ticket});
  }

  static Future<TradingOverlayData> tradingData(String symbol) async {
    final response = await ApiClient.get('/execution/trading-data/?symbol=$symbol');
    if (response == null) return TradingOverlayData.empty();
    return TradingOverlayData.fromJson(Map<String, dynamic>.from(response));
  }
}
