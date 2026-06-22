class PendingOrder {
  final int ticket;
  final String symbol;
  final String type;
  final double volume;
  final double price;

  PendingOrder({
    required this.ticket,
    required this.symbol,
    required this.type,
    required this.volume,
    required this.price,
  });

  factory PendingOrder.fromJson(Map<String, dynamic> json) {
    return PendingOrder(
      ticket: json['ticket'] is int ? json['ticket'] : int.tryParse(json['ticket'].toString()) ?? 0,
      symbol: json['symbol'] ?? 'Unknown',
      type: (json['type_str'] ?? 'ORDER').toString().toUpperCase().replaceAll('_', ' '),
      volume: (json['volume_initial'] ?? 0.0).toDouble(),
      price: (json['price_open'] ?? 0.0).toDouble(),
    );
  }
}