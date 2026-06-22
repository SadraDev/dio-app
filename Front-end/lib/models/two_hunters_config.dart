/// Editable TwoHunters config.
///
/// Backed by the raw JSON map the backend stores (see DEFAULT_TWO_HUNTERS_CONFIG
/// in strategies/engine/config.py). The trimmed shape: NO choch / live_trading
/// sections, `flags` keeps only `order_block_significance`, and a top-level
/// `risk_percent` was added.
class TwoHuntersConfig {
  final Map<String, dynamic> raw;

  TwoHuntersConfig(this.raw);

  factory TwoHuntersConfig.fromJson(Map<String, dynamic> json) =>
      TwoHuntersConfig(Map<String, dynamic>.from(json));

  Map<String, dynamic> toJson() => raw;

  // ── helpers ────────────────────────────────────────────────────────────
  double _d(List<String> path, double def) {
    dynamic node = raw;
    for (final k in path) {
      if (node is Map && node.containsKey(k)) {
        node = node[k];
      } else {
        return def;
      }
    }
    return (node is num) ? node.toDouble() : def;
  }

  String _s(List<String> path, String def) {
    dynamic node = raw;
    for (final k in path) {
      if (node is Map && node.containsKey(k)) {
        node = node[k];
      } else {
        return def;
      }
    }
    return node?.toString() ?? def;
  }

  void _set(List<String> path, dynamic value) {
    Map node = raw;
    for (var i = 0; i < path.length - 1; i++) {
      node[path[i]] = (node[path[i]] is Map)
          ? Map<String, dynamic>.from(node[path[i]])
          : <String, dynamic>{};
      node = node[path[i]];
    }
    node[path.last] = value;
  }

  // ── editable fields ──────────────────────────────────────────────────────
  double get riskPercent => _d(['risk_percent'], 0.005);
  set riskPercent(double v) => _set(['risk_percent'], v);

  double get accountBalance => _d(['account', 'balance'], 2000);
  set accountBalance(double v) => _set(['account', 'balance'], v);

  double get commission => _d(['commission'], 0.0);
  set commission(double v) => _set(['commission'], v);

  double get marginPips => _d(['margin_pips'], 0.1);
  set marginPips(double v) => _set(['margin_pips'], v);

  double get fvgMin => _d(['fvg', 'min_size_pips'], 5.0);
  set fvgMin(double v) => _set(['fvg', 'min_size_pips'], v);

  double get fvgMax => _d(['fvg', 'max_size_pips'], 10.0);
  set fvgMax(double v) => _set(['fvg', 'max_size_pips'], v);

  double get slRatio => _d(['ratios', 'stop_loss'], 1.0);
  set slRatio(double v) => _set(['ratios', 'stop_loss'], v);

  double get tpRatio => _d(['ratios', 'take_profit'], 2.0);
  set tpRatio(double v) => _set(['ratios', 'take_profit'], v);

  int get numHuntMain => _d(['breakout', 'num_hunt_main'], 2).toInt();
  set numHuntMain(int v) => _set(['breakout', 'num_hunt_main'], v);

  String get mboxStart => _s(['mbox_time', 'start'], '04:30');
  set mboxStart(String v) => _set(['mbox_time', 'start'], v);

  String get mboxEnd => _s(['mbox_time', 'end'], '12:29');
  set mboxEnd(String v) => _set(['mbox_time', 'end'], v);

  String get sessionStart => _s(['sessions', 'main', 'start'], '12:30');
  set sessionStart(String v) => _set(['sessions', 'main', 'start'], v);

  String get sessionEnd => _s(['sessions', 'main', 'end'], '22:00');
  set sessionEnd(String v) => _set(['sessions', 'main', 'end'], v);

  // The only flag kept.
  double get orderBlockSignificance =>
      _d(['flags', 'order_block_significance'], 0.02);
  set orderBlockSignificance(double v) =>
      _set(['flags', 'order_block_significance'], v);
}
