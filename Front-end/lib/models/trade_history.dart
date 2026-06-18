class TradeHistory {
  final String pair;
  final String type;
  final double profit;
  final String closedAt;

  TradeHistory({
    required this.pair,
    required this.type,
    required this.profit,
    required this.closedAt,
  });

  factory TradeHistory.fromJson(Map<String, dynamic> json) {
    return TradeHistory(
      pair: json['pair'],
      type: json['type'],
      profit: (json['profit'] as num).toDouble(),
      closedAt: json['closed_at'],
    );
  }
}