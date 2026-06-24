import 'package:flutter/material.dart';
import '../models/two_hunters_config.dart';

class TwoHuntersConfigEditor extends StatefulWidget {
  final TwoHuntersConfig config;
  final Future<void> Function(TwoHuntersConfig) onSave;
  final String buttonText;

  const TwoHuntersConfigEditor({
    super.key,
    required this.config,
    required this.onSave,
    this.buttonText = 'Save config',
  });

  @override
  State<TwoHuntersConfigEditor> createState() => _TwoHuntersConfigEditorState();
}

class _TwoHuntersConfigEditorState extends State<TwoHuntersConfigEditor> {
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

  Future<void> _handleSave() async {
    setState(() { _saving = true; _msg = null; });

    double d(String k, double def) => double.tryParse(_ctrls[k]?.text ?? '') ?? def;
    String s(String k, String def) => (_ctrls[k]?.text.trim().isNotEmpty ?? false) ? _ctrls[k]!.text.trim() : def;

    final cfg = widget.config;
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
      await widget.onSave(cfg);
      if (mounted) setState(() => _msg = 'Saved');
    } catch (e) {
      if (mounted) setState(() => _msg = 'Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _section(String t) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(t, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
  );

  Widget _field(String label, TextEditingController c, {bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
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

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('Risk'),
        _field('Risk percent (fraction, e.g. 0.005)', _c('risk', cfg.riskPercent.toString()), number: true),
        _field('Account balance', _c('balance', cfg.accountBalance.toString()), number: true),
        _field('Commission', _c('commission', cfg.commission.toString()), number: true),

        _section('Entry / Ratios'),
        _field('Margin pips', _c('margin', cfg.marginPips.toString()), number: true),
        _field('Stop-loss ratio', _c('sl', cfg.slRatio.toString()), number: true),
        _field('Take-profit ratio', _c('tp', cfg.tpRatio.toString()), number: true),
        _field('Order block significance', _c('obs', cfg.orderBlockSignificance.toString()), number: true),

        _section('FVG & Breakout'),
        Row(children: [
          Expanded(child: _field('FVG Min', _c('fvgmin', cfg.fvgMin.toString()), number: true)),
          const SizedBox(width: 12),
          Expanded(child: _field('FVG Max', _c('fvgmax', cfg.fvgMax.toString()), number: true)),
        ]),
        _field('Main hunts', _c('hunts', cfg.numHuntMain.toString()), number: true),

        _section('MBox window'),
        Row(children: [
          Expanded(child: _field('Start (HH:MM)', _c('mboxs', cfg.mboxStart))),
          const SizedBox(width: 12),
          Expanded(child: _field('End (HH:MM)', _c('mboxe', cfg.mboxEnd))),
        ]),

        _section('Main session'),
        Row(children: [
          Expanded(child: _field('Start (HH:MM)', _c('sess', cfg.sessionStart))),
          const SizedBox(width: 12),
          Expanded(child: _field('End (HH:MM)', _c('sesse', cfg.sessionEnd))),
        ]),

        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _saving ? null : _handleSave,
            child: _saving
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(widget.buttonText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
        if (_msg != null) ...[
          const SizedBox(height: 10),
          Text(_msg!, style: TextStyle(color: _msg!.startsWith('Error') ? Colors.redAccent : Colors.green)),
        ],
      ],
    );
  }
}