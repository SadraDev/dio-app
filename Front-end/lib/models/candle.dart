class Candle {
  final DateTime time;

  final double open;

  final double high;

  final double low;

  final double close;

  final int volume;

  Candle({
    required this.time,

    required this.open,

    required this.high,

    required this.low,

    required this.close,

    this.volume = 0,
  });

  factory Candle.fromJson(Map<String, dynamic> json) {
    return Candle(
      time: DateTime.parse(json["time"]),

      open: (json["open"]).toDouble(),

      high: (json["high"]).toDouble(),

      low: (json["low"]).toDouble(),

      close: (json["close"]).toDouble(),

      volume: json["volume"] ?? 0,
    );
  }
}
