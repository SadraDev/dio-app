import 'dart:async';
import 'package:flutter/material.dart';

import '../models/two_hunters_config.dart';
import '../models/backtest_result.dart';
import '../services/strategy_service.dart';

/// TwoHunters detail: edit config, start a live process for one symbol, and run
/// / view backtests for one or multiple symbols.
class TwoHuntersScreen extends StatefulWidget {
  final StrategyService strategy;
  const TwoHuntersScreen({super.key, required this.strategy});

  @override
  State<TwoHuntersScreen> createState() => _TwoHuntersScreenState();
}

class _TwoHuntersScreenState extends State<TwoHuntersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  TwoHuntersConfig? _config;
  bool _loadingConfig = true;
  String? _configError;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadConfig();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() {
      _loadingConfig = true;
      _configError = null;
    });
    try {
      final raw = await StrategyApi.getConfig();
      setState(() {
        _config = TwoHuntersConfig.fromJson(raw);
        _loadingConfig = false;
      });
    } catch (e) {
      setState(() {
        _configError = e.toString();
        _loadingConfig = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff0b1220),
      appBar: AppBar(
        backgroundColor: const Color(0xff0b1220),
        title: const Text('TwoHunters', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.green,
          labelColor: Colors.green,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Config'),
            Tab(text: 'Run'),
            Tab(text: 'Backtest'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ConfigTab(
            loading: _loadingConfig,
            error: _configError,
            config: _config,
            onReload: _loadConfig,
          ),
          _RunTab(config: _config),
          _BacktestTab(config: _config),
        ],
      ),
    );
  }
}

/// ── Config tab ───────────────────────────────────────────────────────────
class _ConfigTab extends StatefulWidget {
  final bool loading;
  final String? error;
  final TwoHuntersConfig? config;
  final VoidCallback onReload;

  const _ConfigTab(
      {required this.loading,
      required this.error,
      required this.config,
      required this.onReload});

  @override
  State<_ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends State<_ConfigTab> {
  final _ctrls = <String, TextEditingController>{};
  bool _saving = false;
  String? _msg;

  TextEditingController _c(String key, String initial) =>
      _ctrls.putIfAbsent(key, () => TextEditingController(text: initial));

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final cfg = widget.config;
    if (cfg == null) return;
    setState(() {
      _saving = true;
      _msg = null;
    });
    double d(String k, double def) => double.tryParse(_ctrls[k]?.text ?? '') ?? def;
    String s(String k, String def) =>
        (_ctrls[k]?.text.trim().isNotEmpty ?? false) ? _ctrls[k]!.text.trim() : def;

    cfg.riskPercent = d('risk', cfg.riskPercent);
    cfg.accountBalance = d('balance', cfg.accountBalance);
    cfg.commission = d('commission', cfg.commission);
    cfg.marginPips = d('margin', cfg.marginPips);
    cfg.fvgMin = d('fvgmin', cfg.fvgMin);
    cfg.fvgMax = d('fvgmax', cfg.fvgMax);
    cfg.slRatio = d('sl', cfg.slRatio);
    cfg.tpRatio = d('tp', cfg.tpRatio);
    cfg.numHuntMain = d('hunts', cfg.numHuntMain.toDouble()).toInt();
    cfg.mboxStart = s('mboxs', cfg.mboxStart);
    cfg.mboxEnd = s('mboxe', cfg.mboxEnd);
    cfg.sessionStart = s('sess', cfg.sessionStart);
    cfg.sessionEnd = s('sesse', cfg.sessionEnd);
    cfg.orderBlockSignificance = d('obs', cfg.orderBlockSignificance);

    try {
      await StrategyApi.updateConfig(cfg.toJson());
      setState(() => _msg = 'Saved');
    } catch (e) {
      setState(() => _msg = 'Error: $e');
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.error != null) {
      return _errorBox(widget.error!, widget.onReload);
    }
    final cfg = widget.config!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section('Risk'),
          _num('Risk percent (fraction, e.g. 0.005)', _c('risk', cfg.riskPercent.toString())),
          _num('Account balance', _c('balance', cfg.accountBalance.toString())),
          _num('Commission', _c('commission', cfg.commission.toString())),

          _section('Entry / Ratios'),
          _num('Margin pips', _c('margin', cfg.marginPips.toString())),
          _num('Stop-loss ratio', _c('sl', cfg.slRatio.toString())),
          _num('Take-profit ratio', _c('tp', cfg.tpRatio.toString())),
          _num('Order block significance', _c('obs', cfg.orderBlockSignificance.toString())),

          _section('FVG'),
          _num('Min size (pips)', _c('fvgmin', cfg.fvgMin.toString())),
          _num('Max size (pips)', _c('fvgmax', cfg.fvgMax.toString())),

          _section('Breakout'),
          _num('Main hunts', _c('hunts', cfg.numHuntMain.toString())),

          _section('MBox window'),
          Row(children: [
            Expanded(child: _txt('Start (HH:MM)', _c('mboxs', cfg.mboxStart))),
            const SizedBox(width: 12),
            Expanded(child: _txt('End (HH:MM)', _c('mboxe', cfg.mboxEnd))),
          ]),

          _section('Main session'),
          Row(children: [
            Expanded(child: _txt('Start (HH:MM)', _c('sess', cfg.sessionStart))),
            const SizedBox(width: 12),
            Expanded(child: _txt('End (HH:MM)', _c('sesse', cfg.sessionEnd))),
          ]),

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save config', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          if (_msg != null) ...[
            const SizedBox(height: 10),
            Text(_msg!, style: TextStyle(color: _msg == 'Saved' ? Colors.green : Colors.redAccent)),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(t, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
      );

  Widget _num(String label, TextEditingController c) => _field(label, c, number: true);
  Widget _txt(String label, TextEditingController c) => _field(label, c);

  Widget _field(String label, TextEditingController c, {bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey),
          filled: true,
          fillColor: const Color(0xff162033),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    );
  }
}

/// ── Run tab ──────────────────────────────────────────────────────────────
class _RunTab extends StatefulWidget {
  final TwoHuntersConfig? config;
  const _RunTab({required this.config});

  @override
  State<_RunTab> createState() => _RunTabState();
}

class _RunTabState extends State<_RunTab> {
  final _symbol = TextEditingController(text: 'EURUSD');
  bool _dryRun = true;
  bool _busy = false;
  String? _msg;

  @override
  void dispose() {
    _symbol.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final symbol = _symbol.text.trim().toUpperCase();
    if (symbol.isEmpty) return;

    if (!_dryRun) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xff162033),
          title: const Text('Start live (real orders)?', style: TextStyle(color: Colors.white)),
          content: Text(
            'Dry-run is OFF. The worker will place REAL orders on $symbol through MT5. Continue?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Start live', style: TextStyle(color: Colors.white))),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final state = await StrategyApi.startProcess(symbol,
          config: widget.config?.toJson(), dryRun: _dryRun);
      setState(() => _msg = 'Started ${state.strategy} on ${state.symbol}'
          '${_dryRun ? ' (dry-run)' : ''}. See it on the Strategies / Home screen.');
    } catch (e) {
      setState(() => _msg = 'Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Start a TwoHunters worker for one symbol using the saved config.',
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          TextField(
            controller: _symbol,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Symbol (e.g. EURUSD)',
              labelStyle: const TextStyle(color: Colors.grey),
              filled: true,
              fillColor: const Color(0xff162033),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _dryRun,
            onChanged: (v) => setState(() => _dryRun = v),
            activeThumbColor: Colors.green,
            contentPadding: EdgeInsets.zero,
            title: const Text('Dry-run (no real orders)', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Narrates the full lifecycle and tracks floating P/L without sending orders.',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _dryRun ? Colors.green : Colors.redAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _busy ? null : _start,
              icon: _busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.play_arrow, color: Colors.white),
              label: Text(_dryRun ? 'Start dry-run' : 'Start live',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          if (_msg != null) ...[
            const SizedBox(height: 14),
            Text(_msg!, style: TextStyle(color: _msg!.startsWith('Error') ? Colors.redAccent : Colors.green)),
          ],
        ],
      ),
    );
  }
}

/// ── Backtest tab ─────────────────────────────────────────────────────────
class _BacktestTab extends StatefulWidget {
  final TwoHuntersConfig? config;
  const _BacktestTab({required this.config});

  @override
  State<_BacktestTab> createState() => _BacktestTabState();
}

class _BacktestTabState extends State<_BacktestTab> {
  final _symbols = TextEditingController(text: 'EURUSD, GBPUSD');
  DateTime _start = DateTime.now().subtract(const Duration(days: 30));
  DateTime _end = DateTime.now();
  bool _running = false;
  String? _error;
  BacktestRun? _run;
  Timer? _poll;

  @override
  void dispose() {
    _symbols.dispose();
    _poll?.cancel();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : _end,
      firstDate: DateTime(2001),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _start = picked;
        } else {
          _end = picked;
        }
      });
    }
  }

  Future<void> _run0() async {
    final symbols = _symbols.text
        .split(',')
        .map((s) => s.trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toList();
    if (symbols.isEmpty) return;

    setState(() {
      _running = true;
      _error = null;
      _run = null;
    });
    try {
      var run = await StrategyApi.backtest(
        symbols: symbols,
        startDate: _fmt(_start),
        endDate: _fmt(_end),
        config: widget.config?.toJson(),
      );
      setState(() => _run = run);

      // Poll until done (max ~3 min).
      var attempts = 0;
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 2), (t) async {
        attempts++;
        try {
          run = await StrategyApi.getBacktest(run.id);
          setState(() => _run = run);
          if (run.isDone || attempts > 90) {
            t.cancel();
            setState(() => _running = false);
          }
        } catch (e) {
          t.cancel();
          setState(() {
            _error = e.toString();
            _running = false;
          });
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _symbols,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Symbols (comma-separated)',
              labelStyle: const TextStyle(color: Colors.grey),
              filled: true,
              fillColor: const Color(0xff162033),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _dateField('Start', _start, () => _pickDate(true))),
            const SizedBox(width: 12),
            Expanded(child: _dateField('End', _end, () => _pickDate(false))),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _running ? null : _run0,
              icon: _running
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.science, color: Colors.white),
              label: Text(_running ? 'Running…' : 'Run backtest',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text('Error: $_error', style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 18),
          if (_run != null) _results(_run!),
        ],
      ),
    );
  }

  Widget _dateField(String label, DateTime value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(color: const Color(0xff162033), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, color: Colors.grey, size: 16),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                Text(_fmt(value), style: const TextStyle(color: Colors.white)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _results(BacktestRun run) {
    if (run.status == 'failed') {
      return _box(Text('Backtest failed:\n${run.error}',
          style: const TextStyle(color: Colors.redAccent)));
    }
    if (!run.isDone) {
      return _box(Row(children: const [
        SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent)),
        SizedBox(width: 12),
        Text('Backtest running…', style: TextStyle(color: Colors.white70)),
      ]));
    }
    final sum = run.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Results', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        if (sum != null)
          _box(Column(
            children: [
              _summaryRow('Net gain', '${sum.netGain >= 0 ? '+' : '-'}\$${sum.netGain.abs().toStringAsFixed(2)}',
                  color: sum.netGain >= 0 ? Colors.green : Colors.redAccent),
              _summaryRow('Balance', '\$${sum.initialBalance.toStringAsFixed(0)} → \$${sum.finalBalance.toStringAsFixed(2)}'),
              _summaryRow('Signals', '${sum.totalSignals}'),
              _summaryRow('Win / Loss', '${sum.wins} / ${sum.losses}'),
              _summaryRow('Win rate', '${sum.winRate.toStringAsFixed(1)}%'),
              _summaryRow('Days processed', '${sum.daysProcessed}'),
            ],
          )),
        const SizedBox(height: 16),
        Text('Trades (${run.signals.length})',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (run.signals.isEmpty)
          _box(const Text('No trades generated for this range.', style: TextStyle(color: Colors.grey)))
        else
          ...run.signals.map(_signalRow),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _signalRow(BacktestSignal s) {
    final win = s.outcome == 'win';
    final c = win ? Colors.green : (s.outcome == 'loss' ? Colors.redAccent : Colors.orangeAccent);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xff162033), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(width: 6, height: 36, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(s.symbol, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Text(s.action,
                      style: TextStyle(color: s.action == 'BUY' ? Colors.green : Colors.redAccent, fontSize: 12)),
                ]),
                Text(s.timestamp.replaceFirst('T', ' '),
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${(s.outcome ?? 'pending').toUpperCase()}',
                  style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.bold)),
              Text('${s.gain >= 0 ? '+' : '-'}\$${s.gain.abs().toStringAsFixed(2)}',
                  style: TextStyle(color: s.gain >= 0 ? Colors.green : Colors.redAccent, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {Color color = Colors.white}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _box(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xff162033), borderRadius: BorderRadius.circular(16)),
        child: child,
      );
}

Widget _errorBox(String error, VoidCallback onRetry) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Could not load config:\n$error',
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
