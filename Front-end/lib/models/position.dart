class Position {
  final int ticket;
  final String pair;
  final String type; // BUY / SELL
  final double lot;
  final double entry;
  final double current;
  final double profit;

  Position({
    required this.ticket,
    required this.pair,
    required this.type,
    required this.lot,
    required this.entry,
    required this.current,
    required this.profit,
  });

  factory Position.fromJson(Map<String, dynamic> json) {
    String parsedType = "BUY";
    if (json['type'] is int) {
      parsedType = json['type'] == 0 ? "BUY" : "SELL";
    } else if (json['type_str'] != null) {
      parsedType = json['type_str'].toString().toUpperCase();
    } else if (json['type'] != null) {
      parsedType = json['type'].toString().toUpperCase();
    }

    return Position(
      ticket: json['ticket'] is int ? json['ticket'] : int.tryParse(json['ticket'].toString()) ?? 0,
      pair: json['symbol'] ?? json['pair'] ?? 'Unknown',
      type: parsedType,
      lot: (json['volume'] ?? json['lot'] ?? 0.0).toDouble(),
      entry: (json['price_open'] ?? json['entry'] ?? 0.0).toDouble(),
      current: (json['price_current'] ?? json['current'] ?? 0.0).toDouble(),
      profit: (json['profit'] ?? 0.0).toDouble(),
    );
  }
}