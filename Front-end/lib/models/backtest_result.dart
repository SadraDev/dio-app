/// Models for a backtest run returned by the backend
/// (strategies/views.py -> BacktestRunSerializer + engine.backtest summary).

class BacktestSignal {
  final String symbol;
  final String action; // BUY / SELL
  final String? outcome; // win / loss / force_stoped
  final double entryPrice;
  final double stopLoss;
  final double takeProfit;
  final double gain;
  final double lots;
  final String timestamp;

  BacktestSignal({
    required this.symbol,
    required this.action,
    required this.outcome,
    required this.entryPrice,
    required this.stopLoss,
    required this.takeProfit,
    required this.gain,
    required this.lots,
    required this.timestamp,
  });

  factory BacktestSignal.fromJson(Map<String, dynamic> j) => BacktestSignal(
        symbol: (j['symbol'] ?? '').toString(),
        action: (j['action'] ?? '').toString(),
        outcome: j['outcome']?.toString(),
        entryPrice: (j['entry_price'] ?? 0).toDouble(),
        stopLoss: (j['stop_loss'] ?? 0).toDouble(),
        takeProfit: (j['take_profit'] ?? 0).toDouble(),
        gain: (j['gain'] ?? 0).toDouble(),
        lots: (j['entry_lot'] ?? 0).toDouble(),
        timestamp: (j['timestamp'] ?? '').toString(),
      );
}

class BacktestSummary {
  final double initialBalance;
  final double finalBalance;
  final double netGain;
  final int totalSignals;
  final int wins;
  final int losses;
  final double winRate;
  final int daysProcessed;

  BacktestSummary({
    required this.initialBalance,
    required this.finalBalance,
    required this.netGain,
    required this.totalSignals,
    required this.wins,
    required this.losses,
    required this.winRate,
    required this.daysProcessed,
  });

  factory BacktestSummary.fromJson(Map<String, dynamic> j) => BacktestSummary(
        initialBalance: (j['initial_balance'] ?? 0).toDouble(),
        finalBalance: (j['final_balance'] ?? 0).toDouble(),
        netGain: (j['net_gain'] ?? 0).toDouble(),
        totalSignals: (j['total_signals'] ?? 0).toInt(),
        wins: (j['wins'] ?? 0).toInt(),
        losses: (j['losses'] ?? 0).toInt(),
        winRate: (j['win_rate'] ?? 0).toDouble(),
        daysProcessed: (j['days_processed'] ?? 0).toInt(),
      );
}

class BacktestRun {
  final int id;
  final String status; // pending / running / completed / failed
  final List<String> symbols;
  final String startDate;
  final String endDate;
  final String error;
  final BacktestSummary? summary;
  final List<BacktestSignal> signals;

  BacktestRun({
    required this.id,
    required this.status,
    required this.symbols,
    required this.startDate,
    required this.endDate,
    required this.error,
    required this.summary,
    required this.signals,
  });

  bool get isDone => status == 'completed' || status == 'failed';

  factory BacktestRun.fromJson(Map<String, dynamic> j) {
    final results = (j['results'] is Map)
        ? Map<String, dynamic>.from(j['results'])
        : <String, dynamic>{};

    BacktestSummary? summary;
    final signals = <BacktestSignal>[];
    results.forEach((key, value) {
      if (key == 'summary' && value is Map) {
        summary = BacktestSummary.fromJson(Map<String, dynamic>.from(value));
      } else if (value is List) {
        for (final s in value) {
          if (s is Map) {
            signals.add(BacktestSignal.fromJson(Map<String, dynamic>.from(s)));
          }
        }
      }
    });

    return BacktestRun(
      id: (j['id'] ?? 0).toInt(),
      status: (j['status'] ?? 'pending').toString(),
      symbols: (j['symbols'] is List)
          ? (j['symbols'] as List).map((e) => e.toString()).toList()
          : <String>[],
      startDate: (j['start_date'] ?? '').toString(),
      endDate: (j['end_date'] ?? '').toString(),
      error: (j['error'] ?? '').toString(),
      summary: summary,
      signals: signals,
    );
  }
}
