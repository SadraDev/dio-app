class TradeHistory {
  final String pair;
  final String type;
  final double profit;
  final double commission;
  final double swap;
  final String closedAt;

  TradeHistory({
    required this.pair,
    required this.type,
    required this.profit,
    required this.commission,
    required this.swap,
    required this.closedAt,
  });

  factory TradeHistory.fromJson(Map<String, dynamic> json) {
    // 1. Parse Type
    String parsedType = "BUY";
    if (json['type'] is int) {
      parsedType = json['type'] == 0 ? "BUY" : "SELL";
    } else if (json['type_str'] != null) {
      parsedType = json['type_str'].toString().toUpperCase();
    }

    // 2. Parse Financials
    final double rawProfit = (json['profit'] ?? 0.0).toDouble();
    final double commission = (json['commission'] ?? 0.0).toDouble();
    final double swap = (json['swap'] ?? 0.0).toDouble();

    // NET Profit = Gross Profit + Commission + Swap
    final double netProfit = rawProfit + commission + swap;

    // 3. Parse Time
    String timeStr = "Unknown";
    final rawTime = json['time'] ?? json['time_setup'] ?? json['closed_at'];

    if (rawTime is int) {
      final dt = DateTime.fromMillisecondsSinceEpoch(rawTime > 9999999999 ? rawTime : rawTime * 1000);
      timeStr = "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } else if (rawTime != null) {
      timeStr = rawTime.toString();
      if (timeStr.contains('T')) {
        timeStr = timeStr.split('T').join(' ').split('.').first;
      }
    }

    return TradeHistory(
      pair: json['symbol'] ?? json['pair'] ?? 'Unknown',
      type: parsedType,
      profit: netProfit,
      commission: commission,
      swap: swap,
      closedAt: timeStr,
    );
  }
}