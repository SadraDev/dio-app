import 'dart:convert';

class TradingOverlayData {
  final List<OpenPosition> positions;
  final List<PendingOrder> orders;
  final List<ConcludedDeal> deals;

  TradingOverlayData({
    required this.positions,
    required this.orders,
    required this.deals,
  });

  factory TradingOverlayData.empty() {
    return TradingOverlayData(positions: [], orders: [], deals: []);
  }

  factory TradingOverlayData.fromJson(Map<String, dynamic> json) {
    return TradingOverlayData(
      positions: (json['positions'] as List? ?? [])
          .map((e) => OpenPosition.fromJson(e))
          .toList(),
      orders: (json['orders'] as List? ?? [])
          .map((e) => PendingOrder.fromJson(e))
          .toList(),
      deals: (json['deals'] as List? ?? [])
          .map((e) => ConcludedDeal.fromJson(e))
          .toList(),
    );
  }
}

class OpenPosition {
  final int ticket;
  final double volume;
  final double priceOpen;
  final double sl;
  final double tp;
  final String typeStr; // 'buy' or 'sell'
  final double profit;

  OpenPosition({
    required this.ticket,
    required this.volume,
    required this.priceOpen,
    required this.sl,
    required this.tp,
    required this.typeStr,
    required this.profit,
  });

  factory OpenPosition.fromJson(Map<String, dynamic> json) {
    return OpenPosition(
      ticket: json['ticket'] ?? 0,
      volume: (json['volume'] ?? 0.0).toDouble(),
      priceOpen: (json['price_open'] ?? 0.0).toDouble(),
      sl: (json['sl'] ?? 0.0).toDouble(),
      tp: (json['tp'] ?? 0.0).toDouble(),
      typeStr: json['type_str'] ?? 'buy',
      profit: (json['profit'] ?? 0.0).toDouble(),
    );
  }
}

class PendingOrder {
  final int ticket;
  final double volumeInitial;
  final double priceOpen;
  final String typeStr; // 'buy_limit', 'sell_limit'

  PendingOrder({
    required this.ticket,
    required this.volumeInitial,
    required this.priceOpen,
    required this.typeStr,
  });

  factory PendingOrder.fromJson(Map<String, dynamic> json) {
    return PendingOrder(
      ticket: json['ticket'] ?? 0,
      volumeInitial: (json['volume_initial'] ?? 0.0).toDouble(),
      priceOpen: (json['price_open'] ?? 0.0).toDouble(),
      typeStr: json['type_str'] ?? 'buy_limit',
    );
  }
}

class ConcludedDeal {
  final int ticket;
  final int positionId;
  final DateTime time;
  final double price;
  final double volume;
  final String typeStr;  // 'buy', 'sell'
  final String entryStr; // 'in', 'out'
  final double profit;

  ConcludedDeal({
    required this.ticket,
    required this.positionId,
    required this.time,
    required this.price,
    required this.volume,
    required this.typeStr,
    required this.entryStr,
    required this.profit,
  });

  factory ConcludedDeal.fromJson(Map<String, dynamic> json) {
    // MetaTrader 5 historical deals use unix timestamps in seconds
    final int rawSeconds = json['time'] ?? 0;
    return ConcludedDeal(
      ticket: json['ticket'] ?? 0,
      positionId: json['position_id'] ?? 0,
      time: DateTime.fromMillisecondsSinceEpoch(rawSeconds * 1000, isUtc: true),
      price: (json['price'] ?? 0.0).toDouble(),
      volume: (json['volume'] ?? 0.0).toDouble(),
      typeStr: json['type_str'] ?? 'buy',
      entryStr: json['entry_str'] ?? 'in',
      profit: (json['profit'] ?? 0.0).toDouble(),
    );
  }
}