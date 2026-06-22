/// Live state model for a single strategy worker (one strategy on one symbol).
///
/// Field names / enum strings mirror the payload the Django backend now
/// publishes over Channels (see strategies/manager.py -> Worker.to_state), so
/// the SAME model parses the WebSocket feed and the REST snapshot.

enum WorkerPhase {
  stopped,
  paused,
  huntingPhase, // displayed as "HUNTING_PHASE x/N"
  orderPlaced, // pending order is live, not yet filled
  positionPlaced, // position opened / order filled
  monitoringSignal, // tracking the open signal until it closes
  done,
  unknown,
}

WorkerPhase workerPhaseFromString(String? v) {
  switch (v) {
    case 'STOPPED':
      return WorkerPhase.stopped;
    case 'PAUSED':
      return WorkerPhase.paused;
    case 'HUNTING_PHASE':
      return WorkerPhase.huntingPhase;
    case 'ORDER_PLACED':
      return WorkerPhase.orderPlaced;
    case 'POSITION_PLACED':
      return WorkerPhase.positionPlaced;
    case 'MONITORING_SIGNAL':
      return WorkerPhase.monitoringSignal;
    case 'DONE':
      return WorkerPhase.done;
    default:
      return WorkerPhase.unknown;
  }
}

/// The currently open signal a worker is tracking (null when none).
class ActiveSignal {
  final String side; // BUY / SELL
  final double entry;
  final double slPips;
  final double tpPips;
  final double lots;
  final double gain; // floating or realized P/L in account currency
  final bool isOrder; // true while still a pending order (not filled)
  final bool riskFree; // SL moved to break-even (sl_adjusted_count > 0)
  final int? ticket;

  ActiveSignal({
    required this.side,
    required this.entry,
    required this.slPips,
    required this.tpPips,
    required this.lots,
    required this.gain,
    required this.isOrder,
    required this.riskFree,
    this.ticket,
  });

  ActiveSignal copyWith({double? gain, bool? isOrder, bool? riskFree}) {
    return ActiveSignal(
      side: side,
      entry: entry,
      slPips: slPips,
      tpPips: tpPips,
      lots: lots,
      gain: gain ?? this.gain,
      isOrder: isOrder ?? this.isOrder,
      riskFree: riskFree ?? this.riskFree,
      ticket: ticket,
    );
  }

  factory ActiveSignal.fromJson(Map<String, dynamic> json) {
    return ActiveSignal(
      side: (json['side'] ?? 'BUY').toString(),
      entry: (json['entry'] ?? 0.0).toDouble(),
      slPips: (json['sl_pips'] ?? 0.0).toDouble(),
      tpPips: (json['tp_pips'] ?? 0.0).toDouble(),
      lots: (json['lots'] ?? 0.0).toDouble(),
      gain: (json['gain'] ?? 0.0).toDouble(),
      isOrder: json['is_order'] ?? false,
      riskFree: json['risk_free'] ?? false,
      ticket: json['ticket'],
    );
  }
}

/// Per-worker tally for the current trading day.
class WorkerToday {
  final String? outcome; // win / loss / force_stoped / null
  final double netGain;

  WorkerToday({this.outcome, this.netGain = 0.0});

  factory WorkerToday.fromJson(Map<String, dynamic>? json) {
    if (json == null) return WorkerToday();
    return WorkerToday(
      outcome: json['outcome'],
      netGain: (json['net_gain'] ?? 0.0).toDouble(),
    );
  }
}

class WorkerState {
  final String strategy; // e.g. "TwoHunters"
  final String symbol; // e.g. "EURUSD"
  final bool running;
  final bool paused;
  final WorkerPhase phase;
  final String message; // human-readable narration line
  final int huntCurrent; // current hunt index (0..huntTotal)
  final int huntTotal; // total hunts in the phase (e.g. 2)
  final bool sessionOpen;
  final ActiveSignal? activeSignal;
  final WorkerToday today;
  final Map<String, dynamic> config; // config this worker is running with
  final bool dryRun;
  final DateTime updatedAt;

  WorkerState({
    required this.strategy,
    required this.symbol,
    required this.running,
    required this.phase,
    required this.message,
    required this.huntCurrent,
    required this.huntTotal,
    required this.sessionOpen,
    required this.today,
    required this.updatedAt,
    this.paused = false,
    this.activeSignal,
    this.config = const {},
    this.dryRun = true,
  });

  /// Stable key used to identify a worker across updates.
  String get key => '$strategy::$symbol';

  bool get isInTrade =>
      phase == WorkerPhase.orderPlaced ||
      phase == WorkerPhase.positionPlaced ||
      phase == WorkerPhase.monitoringSignal;

  bool get isHunting => phase == WorkerPhase.huntingPhase;

  /// Short label for the status pill.
  String get statusLabel {
    if (paused) return 'PAUSED';
    if (!running) return 'STOPPED';
    switch (phase) {
      case WorkerPhase.huntingPhase:
        return 'HUNTING $huntCurrent/$huntTotal';
      case WorkerPhase.orderPlaced:
        return 'ORDER PLACED';
      case WorkerPhase.positionPlaced:
        return 'POSITION PLACED';
      case WorkerPhase.monitoringSignal:
        return 'MONITORING';
      case WorkerPhase.done:
        return 'DONE';
      case WorkerPhase.paused:
        return 'PAUSED';
      case WorkerPhase.stopped:
        return 'STOPPED';
      default:
        return 'IDLE';
    }
  }

  factory WorkerState.fromJson(Map<String, dynamic> json) {
    return WorkerState(
      strategy: (json['strategy'] ?? 'Strategy').toString(),
      symbol: (json['symbol'] ?? '').toString(),
      running: json['running'] ?? false,
      paused: json['paused'] ?? false,
      phase: workerPhaseFromString(json['phase']?.toString()),
      message: (json['message'] ?? '').toString(),
      huntCurrent: json['hunt_current'] ?? 0,
      huntTotal: json['hunt_total'] ?? 2,
      sessionOpen: json['session_open'] ?? false,
      activeSignal: json['active_signal'] == null
          ? null
          : ActiveSignal.fromJson(
              Map<String, dynamic>.from(json['active_signal'])),
      today: WorkerToday.fromJson(json['today'] == null
          ? null
          : Map<String, dynamic>.from(json['today'])),
      config: json['config'] == null
          ? const {}
          : Map<String, dynamic>.from(json['config']),
      dryRun: json['dry_run'] ?? true,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  WorkerState copyWith({
    bool? running,
    bool? paused,
    WorkerPhase? phase,
    String? message,
    int? huntCurrent,
    int? huntTotal,
    bool? sessionOpen,
    ActiveSignal? activeSignal,
    bool clearSignal = false,
    WorkerToday? today,
    Map<String, dynamic>? config,
    bool? dryRun,
    DateTime? updatedAt,
  }) {
    return WorkerState(
      strategy: strategy,
      symbol: symbol,
      running: running ?? this.running,
      paused: paused ?? this.paused,
      phase: phase ?? this.phase,
      message: message ?? this.message,
      huntCurrent: huntCurrent ?? this.huntCurrent,
      huntTotal: huntTotal ?? this.huntTotal,
      sessionOpen: sessionOpen ?? this.sessionOpen,
      activeSignal: clearSignal ? null : (activeSignal ?? this.activeSignal),
      today: today ?? this.today,
      config: config ?? this.config,
      dryRun: dryRun ?? this.dryRun,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

/// A single narration event for the "Recent activity" feed.
class StrategyEvent {
  final String symbol;
  final String strategy;
  final String message;
  final DateTime time;

  StrategyEvent({
    required this.symbol,
    required this.strategy,
    required this.message,
    required this.time,
  });
}
