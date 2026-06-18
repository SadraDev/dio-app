class Position {
  final String pair;
  final String type; // BUY / SELL
  final double lot;
  final double entry;
  final double current;
  final double profit;

  Position({
    required this.pair,
    required this.type,
    required this.lot,
    required this.entry,
    required this.current,
    required this.profit,
  });

  factory Position.fromJson(Map<String, dynamic> json) {
    return Position(
      pair: json['pair'],
      type: json['type'],
      lot: (json['lot'] as num).toDouble(),
      entry: (json['entry'] as num).toDouble(),
      current: (json['current'] as num).toDouble(),
      profit: (json['profit'] as num).toDouble(),
    );
  }
}