class AccountData {
  final double balance;
  final double equity;
  final double margin;
  final double freeMargin;
  final double marginLevel;
  final String currency;
  final int leverage;

  AccountData({
    required this.balance,
    required this.equity,
    required this.margin,
    required this.freeMargin,
    required this.marginLevel,
    required this.currency,
    required this.leverage,
  });

  factory AccountData.fromJson(Map<String, dynamic> json) {
    return AccountData(
      balance: (json['balance'] as num).toDouble(),
      equity: (json['equity'] as num).toDouble(),
      margin: (json['margin'] as num).toDouble(),
      freeMargin: (json['free_margin'] as num).toDouble(),
      marginLevel: (json['margin_level'] as num).toDouble(),
      currency: json['currency'] ?? 'USD',
      leverage: json['leverage'] ?? 0
    );
  }
}