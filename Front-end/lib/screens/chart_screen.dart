import 'dart:async';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../models/candle.dart';
import '../models/trading_data.dart';
import '../services/market_service.dart';
import '../services/storage_service.dart';
import '../services/trade_service.dart';
import '../widgets/trade_dialog.dart';
import '../widgets/positions_sheet.dart';

enum _DragTarget { entry, sl, tp }

class ChartScreen extends StatefulWidget {
  const ChartScreen({super.key});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  final MarketService marketService = MarketService();
  ChartSeriesController? _chartController;
  ChartAxisController? _xAxisController;

  final TextEditingController _symbolController =
  TextEditingController(text: "EURUSD");
  final List<String> timeframes = ["M1", "M5", "M15", "H1", "H4", "D1"];
  String selectedTimeframe = "M1";

  static const int pageSize = 60;

  List<Candle> candles = [];
  bool loading = false;
  bool isFetching = false;
  bool hasReachedEnd = false;
  DateTime? lastFetchTime;

  TradingOverlayData _overlayData = TradingOverlayData.empty();
  Timer? _timer;

  late ZoomPanBehavior zoomPanBehavior;

  // ── dynamic axes boundaries & auto-scale flags ────────────────────
  bool _autoScaleY = true;
  double? _yMin;
  double? _yMax;

  // ── pending-order ticket state ────────────────────────────────────
  bool _ticketActive = false;
  bool _panWhileTicketing = false;
  bool _isSubmitting = false;

  String _ticketSide = 'buy_limit';
  double _volume = 0.01;
  double _entryPrice = 0.0;
  double _slPrice = 0.0;
  double _tpPrice = 0.0;
  _DragTarget _dragTarget = _DragTarget.entry;

  final _volCtrl = TextEditingController(text: "0.01");
  final _entryCtrl = TextEditingController();
  final _slCtrl = TextEditingController();
  final _tpCtrl = TextEditingController();

  // ── Interactive Position State ────────────────────────────────────
  int? _selectedTicket;
  String? _modTarget;
  double? _modPrice;
  bool _isModifying = false;

  @override
  void initState() {
    super.initState();
    _setPanZoom(locked: false);
    _bootstrap();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _symbolController.dispose();
    _volCtrl.dispose();
    _entryCtrl.dispose();
    _slCtrl.dispose();
    _tpCtrl.dispose();
    super.dispose();
  }

  String get symbol => _symbolController.text.trim();

  static List<Candle> _clean(List<Candle> input) => input
      .where((c) =>
  c.time.year >= 2000 &&
      c.open > 0 && c.high > 0 &&
      c.low > 0 && c.close > 0)
      .toList();

  DateTime _snapToCandle(DateTime target) {
    if (candles.isEmpty) return target;
    int low = 0;
    int high = candles.length - 1;

    while (low <= high) {
      int mid = low + ((high - low) >> 1);
      if (candles[mid].time == target) return candles[mid].time;
      if (candles[mid].time.isBefore(target)) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    if (high < 0) return candles.first.time;
    if (low >= candles.length) return candles.last.time;

    int diffLow = candles[low].time.difference(target).inMilliseconds.abs();
    int diffHigh = candles[high].time.difference(target).inMilliseconds.abs();
    return (diffLow < diffHigh) ? candles[low].time : candles[high].time;
  }

  void _updateYRange() {
    if (!_autoScaleY || candles.isEmpty) return;

    double minPrice = candles.first.low;
    double maxPrice = candles.first.high;

    for (var c in candles) {
      if (c.low < minPrice) minPrice = c.low;
      if (c.high > maxPrice) maxPrice = c.high;
    }

    double padding = (maxPrice - minPrice) * 0.05;
    if (padding == 0) padding = 0.001;

    setState(() {
      _yMin = minPrice - padding;
      _yMax = maxPrice + padding;
    });
  }

  void _setPanZoom({required bool locked}) {
    zoomPanBehavior = ZoomPanBehavior(
      enablePinching: !locked,
      enablePanning: !locked,
      zoomMode: ZoomMode.xy,
    );
  }

  Future<void> _bootstrap() async {
    final cached =
    _clean(await StorageService.loadCachedCandles(symbol, selectedTimeframe));

    if (cached.isNotEmpty && mounted) {
      setState(() => candles = cached);
      _updateYRange();
    }
    await fetchCandles();
    _fetchOverlay();
  }

  Future<void> _fetchOverlay() async {
    try {
      final data = await TradeService.tradingData(symbol);
      if (mounted) setState(() => _overlayData = data);
    } catch (e) {
      debugPrint("overlay error: $e");
    }
  }

  Future<void> fetchCandles() async {
    setState(() {
      loading = candles.isEmpty;
      hasReachedEnd = false;
    });

    try {
      final result = await marketService.getCandles(
        symbol: symbol,
        timeframe: selectedTimeframe,
        count: pageSize,
      );

      if (!mounted) return;
      setState(() {
        candles = _clean(result);
        _updateYRange();
      });
      StorageService.cacheCandles(symbol, selectedTimeframe, candles);
      _startPolling();
    } catch (e) {
      debugPrint("fetch error: $e");
    }
    if (mounted) setState(() => loading = false);
  }

  // Updated _fetchMore: Cleaned up for manual button triggering
  Future<void> _fetchMore() async {
    if (isFetching || hasReachedEnd || candles.isEmpty) return;

    setState(() => isFetching = true);

    try {
      final older = _clean(await marketService.getCandles(
        symbol: symbol,
        timeframe: selectedTimeframe,
        count: pageSize,
        before: candles.first.time,
      ));

      if (!mounted) return;
      if (older.isEmpty) {
        setState(() => hasReachedEnd = true);
        return;
      }
      if (older.last.time.isAtSameMomentAs(candles.first.time)) {
        older.removeLast();
      }

      if (older.isNotEmpty) {
        int oldLen = candles.length;
        double? oldFactor = _xAxisController?.zoomFactor;
        double? oldPos = _xAxisController?.zoomPosition;

        setState(() {
          candles.insertAll(0, older);
          _updateYRange();
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_xAxisController != null && oldFactor != null && oldPos != null) {
            double oldTotal = oldLen.toDouble();
            double newTotal = candles.length.toDouble();

            double visibleCandles = oldTotal * oldFactor;
            double newFactor = visibleCandles / newTotal;
            double newStartIdx = (oldTotal * oldPos) + older.length;
            double newPos = newStartIdx / newTotal;

            _xAxisController!.zoomFactor = newFactor.clamp(0.01, 1.0);
            _xAxisController!.zoomPosition = newPos.clamp(0.0, 1.0);
          }
        });

        StorageService.cacheCandles(symbol, selectedTimeframe, candles);
      } else {
        setState(() => hasReachedEnd = true);
      }
    } catch (e) {
      debugPrint("fetchMore error: $e");
    } finally {
      if (mounted) setState(() => isFetching = false);
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || candles.isEmpty) return;
      _fetchOverlay();
      try {
        final result = await marketService.getCandles(
          symbol: symbol,
          timeframe: selectedTimeframe,
          count: 1,
        );
        if (result.isEmpty) return;

        final newCandle = result.last;
        if (newCandle.time.year < 2000 || newCandle.open <= 0) return;
        final lastIndex = candles.length - 1;

        if (candles[lastIndex].time == newCandle.time) {
          candles[lastIndex] = newCandle;
          _chartController?.updateDataSource(updatedDataIndexes: [lastIndex]);
        } else {
          candles.add(newCandle);
          _chartController?.updateDataSource(addedDataIndexes: [candles.length - 1]);
        }

        if (_autoScaleY && (newCandle.high > (_yMax ?? 0) || newCandle.low < (_yMin ?? double.infinity))) {
          _updateYRange();
        }

      } catch (e) {
        debugPrint("poll error: $e");
      }
    });
  }

  void _reload() {
    setState(() {
      _autoScaleY = true;
      _selectedTicket = null;
      _modTarget = null;
    });
    if (_xAxisController != null) {
      _xAxisController!.zoomFactor = 1.0;
      _xAxisController!.zoomPosition = 0.0;
    }
    _bootstrap();
  }

  List<ConcludedDeal> get _buyDeals {
    if (candles.isEmpty) return [];
    final start = candles.first.time.subtract(const Duration(seconds: 1));
    final end = candles.last.time.add(const Duration(seconds: 1));
    return _overlayData.deals.where((d) =>
    d.typeStr.toLowerCase() == 'buy' && d.price > 0 && d.time.year >= 2000 &&
        !d.time.isBefore(start) && !d.time.isAfter(end)).toList();
  }

  List<ConcludedDeal> get _sellDeals {
    if (candles.isEmpty) return [];
    final start = candles.first.time.subtract(const Duration(seconds: 1));
    final end = candles.last.time.add(const Duration(seconds: 1));
    return _overlayData.deals.where((d) =>
    d.typeStr.toLowerCase() == 'sell' && d.price > 0 && d.time.year >= 2000 &&
        !d.time.isBefore(start) && !d.time.isAfter(end)).toList();
  }

  dynamic get _annotationX {
    if (_xAxisController != null && candles.isNotEmpty) {
      final pos = _xAxisController!.zoomPosition;
      final factor = _xAxisController!.zoomFactor;
      final minIdx = pos * candles.length;
      final maxIdx = (pos + factor) * candles.length;

      int targetIdx = (minIdx + ((maxIdx - minIdx) * 0.7)).toInt();
      return candles[targetIdx.clamp(0, candles.length - 1)].time;
    }
    return candles.isNotEmpty ? candles.last.time : DateTime.now();
  }

  void _startMod(OpenPosition pos, String target) {
    setState(() {
      _modTarget = target;
      _modPrice = (target == 'sl' && pos.sl > 0) ? pos.sl :
      (target == 'tp' && pos.tp > 0) ? pos.tp : pos.priceOpen;
      _setPanZoom(locked: true);
    });
  }

  void _cancelMod() {
    setState(() {
      _modTarget = null;
      _modPrice = null;
      _setPanZoom(locked: false);
    });
  }

  Future<void> _closePosition(int ticket) async {
    setState(() => _isModifying = true);
    try {
      await TradeService.closePosition(ticket);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Position closed"), backgroundColor: Colors.green));
    } catch(e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Close failed: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) {
        setState(() { _isModifying = false; _selectedTicket = null; });
        _fetchOverlay();
      }
    }
  }

  Future<void> _submitMod() async {
    if (_selectedTicket == null || _modTarget == null || _modPrice == null) return;
    setState(() => _isModifying = true);

    try {
      final pos = _overlayData.positions.firstWhere((p) => p.ticket == _selectedTicket);
      double? newSl = _modTarget == 'sl' ? _modPrice : (pos.sl > 0 ? pos.sl : null);
      double? newTp = _modTarget == 'tp' ? _modPrice : (pos.tp > 0 ? pos.tp : null);

      await TradeService.modifyPosition(pos.ticket, sl: newSl, tp: newTp);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Position modified successfully"), backgroundColor: Colors.green));
    } catch(e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Modify failed: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) {
        setState(() {
          _isModifying = false; _selectedTicket = null; _modTarget = null; _modPrice = null;
          _setPanZoom(locked: false);
        });
        _fetchOverlay();
      }
    }
  }

  Widget _buildTextActionBox(String text, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white38),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _startTicket() {
    final base = candles.isNotEmpty ? candles.last.close : 1.0;
    setState(() {
      _ticketActive = true;
      _ticketSide = 'buy_limit';
      _entryPrice = base;
      _slPrice = 0.0;
      _tpPrice = 0.0;
      _dragTarget = _DragTarget.entry;
      _panWhileTicketing = false;
      _volume = double.tryParse(_volCtrl.text) ?? 0.01;
      _entryCtrl.text = base.toStringAsFixed(5);
      _slCtrl.clear();
      _tpCtrl.clear();
      _setPanZoom(locked: true);
    });
  }

  void _cancelTicket() {
    setState(() {
      _ticketActive = false;
      _setPanZoom(locked: false);
    });
  }

  void _applyDrag(double price) {
    setState(() {
      switch (_dragTarget) {
        case _DragTarget.entry:
          _entryPrice = price;
          _entryCtrl.text = price.toStringAsFixed(5);
          break;
        case _DragTarget.sl:
          _slPrice = price;
          _slCtrl.text = price.toStringAsFixed(5);
          break;
        case _DragTarget.tp:
          _tpPrice = price;
          _tpCtrl.text = price.toStringAsFixed(5);
          break;
      }
    });
  }

  Future<void> _submitTicket() async {
    setState(() => _isSubmitting = true);

    try {
      await TradeService.placePending(
        symbol: symbol,
        volume: double.tryParse(_volCtrl.text) ?? _volume,
        side: _ticketSide,
        price: double.tryParse(_entryCtrl.text) ?? _entryPrice,
        sl: (double.tryParse(_slCtrl.text) ?? 0) > 0 ? double.parse(_slCtrl.text) : null,
        tp: (double.tryParse(_tpCtrl.text) ?? 0) > 0 ? double.parse(_tpCtrl.text) : null,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Pending order placed!"),
        backgroundColor: Colors.green,
      ));
      _fetchOverlay();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Order failed: $e"),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _ticketActive = false;
          _setPanZoom(locked: false);
        });
      }
    }
  }

  Future<void> _openManageSheet() async {
    await _fetchOverlay();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => PositionsSheet(
        symbol: symbol,
        data: _overlayData,
        onChanged: _fetchOverlay,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _topBar(),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : _chart(),
          ),
          _ticketActive ? _ticketPanel() : _tradeControls(),
        ],
      ),
    );
  }

  Widget _topBar() {
    final posCount = _overlayData.positions.length;

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: TextField(
              controller: _symbolController,
              onSubmitted: (_) => _reload(),
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                filled: true,
                fillColor: Color(0xff162033),
                border: OutlineInputBorder(borderSide: BorderSide.none),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xff162033),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<String>(
              value: selectedTimeframe,
              dropdownColor: const Color(0xff162033),
              style: const TextStyle(color: Colors.white),
              underline: const SizedBox(),
              items: timeframes
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) {
                setState(() => selectedTimeframe = v!);
                _reload();
              },
            ),
          ),
          const Spacer(),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                onPressed: _openManageSheet,
                icon: const Icon(Icons.list_alt, color: Colors.white),
                tooltip: "Positions & orders",
              ),
              if (posCount > 0)
                Positioned(
                  right: 4,
                  top: 2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                        color: Colors.blueAccent, shape: BoxShape.circle),
                    child: Text("$posCount",
                        style: const TextStyle(color: Colors.white, fontSize: 9)),
                  ),
                ),
            ],
          ),
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _tradeControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: _btn("New Order", Colors.blueAccent, () async {
              final placed = await showDialog<bool>(
                context: context,
                builder: (_) => TradeDialog(symbol: symbol, isPending: false),
              );
              if (placed == true) _fetchOverlay();
            }),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: _btn("Set Limit", const Color(0xff162033), _startTicket),
          ),
        ],
      ),
    );
  }

  Widget _btn(String text, Color color, VoidCallback onPressed) {
    return SizedBox(
      height: 45,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onPressed,
        child: Text(text,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _ticketPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xff111827),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'buy_limit', label: Text("Buy Limit")),
                    ButtonSegment(value: 'sell_limit', label: Text("Sell Limit")),
                  ],
                  selected: {_ticketSide},
                  onSelectionChanged: (s) => setState(() => _ticketSide = s.first),
                  style: ButtonStyle(
                    foregroundColor: WidgetStateProperty.all(Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _numInput(_volCtrl, "Volume", null)),
              const SizedBox(width: 8),
              Expanded(child: _numInput(_entryCtrl, "Entry", _DragTarget.entry)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _numInput(_slCtrl, "SL", _DragTarget.sl)),
              const SizedBox(width: 8),
              Expanded(child: _numInput(_tpCtrl, "TP", _DragTarget.tp)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ChoiceChip(
                label: const Text("Move chart", style: TextStyle(fontSize: 11)),
                selected: _panWhileTicketing,
                onSelected: (_) => setState(() {
                  _panWhileTicketing = true;
                  _setPanZoom(locked: false);
                }),
                selectedColor: Colors.green,
                backgroundColor: const Color(0xff0f172a),
                labelStyle: TextStyle(
                    color: _panWhileTicketing ? Colors.white : Colors.white54),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text("Drag line", style: TextStyle(fontSize: 11)),
                selected: !_panWhileTicketing,
                onSelected: (_) => setState(() {
                  _panWhileTicketing = false;
                  _setPanZoom(locked: true);
                }),
                selectedColor: Colors.blueAccent,
                backgroundColor: const Color(0xff0f172a),
                labelStyle: TextStyle(
                    color: !_panWhileTicketing ? Colors.white : Colors.white54),
              ),
            ],
          ),
          if (!_panWhileTicketing) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Drag line: ",
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                _dragChip("Entry", _DragTarget.entry),
                _dragChip("SL", _DragTarget.sl),
                _dragChip("TP", _DragTarget.tp),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSubmitting ? null : _cancelTicket,
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent)),
                  child: const Text("Cancel", style: TextStyle(color: Colors.redAccent)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                  onPressed: _isSubmitting ? null : _submitTicket,
                  child: _isSubmitting
                      ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                      : const Text("Place Order", style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _numInput(TextEditingController c, String label, _DragTarget? target) {
    return TextField(
      controller: c,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (v) {
        final d = double.tryParse(v);
        if (d == null) return;
        setState(() {
          if (target == _DragTarget.entry) _entryPrice = d;
          if (target == _DragTarget.sl) _slPrice = d;
          if (target == _DragTarget.tp) _tpPrice = d;
        });
      },
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 12),
        isDense: true,
        filled: true,
        fillColor: const Color(0xff0f172a),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _dragChip(String label, _DragTarget target) {
    final selected = _dragTarget == target;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: selected,
        onSelected: (_) => setState(() => _dragTarget = target),
        selectedColor: Colors.blueAccent,
        backgroundColor: const Color(0xff0f172a),
        labelStyle: TextStyle(color: selected ? Colors.white : Colors.white54),
      ),
    );
  }

  List<PlotBand> _buildPlotBands() {
    final bands = <PlotBand>[];

    if (_ticketActive) {
      final isBuy = _ticketSide.contains('buy');
      bands.add(_line(_entryPrice, isBuy ? Colors.green : Colors.red,
          '${_ticketSide.toUpperCase()} ${_entryPrice.toStringAsFixed(5)}', dashed: true));
      if (_slPrice > 0) bands.add(_line(_slPrice, Colors.redAccent, 'SL ${_slPrice.toStringAsFixed(5)}'));
      if (_tpPrice > 0) bands.add(_line(_tpPrice, Colors.greenAccent, 'TP ${_tpPrice.toStringAsFixed(5)}'));
    }

    for (final pos in _overlayData.positions) {
      if (pos.priceOpen > 0) {
        final isSelected = pos.ticket == _selectedTicket;
        final isBuy = pos.typeStr.toLowerCase() == 'buy';

        bands.add(_line(
          pos.priceOpen,
          isBuy ? Colors.greenAccent : Colors.redAccent,
          'POS #${pos.ticket} ${pos.typeStr.toUpperCase()} ${pos.volume}',
          width: isSelected ? 2.5 : 1.5,
        ));

        if (pos.sl > 0 && !(isSelected && _modTarget == 'sl')) {
          bands.add(_line(pos.sl, Colors.red, 'SL', width: 1, dashed: true, fontSize: 9));
        }
        if (pos.tp > 0 && !(isSelected && _modTarget == 'tp')) {
          bands.add(_line(pos.tp, Colors.green, 'TP', width: 1, dashed: true, fontSize: 9));
        }
      }
    }

    if (_modTarget != null && _modPrice != null) {
      bands.add(_line(
        _modPrice!,
        _modTarget == 'sl' ? Colors.orangeAccent : Colors.greenAccent,
        'DRAG TO SET ${_modTarget!.toUpperCase()}',
        width: 2.0,
        dashed: true,
      ));
    }

    for (final ord in _overlayData.orders) {
      if (ord.priceOpen > 0) {
        bands.add(_line(
          ord.priceOpen, Colors.amber,
          'LIMIT #${ord.ticket} ${ord.typeStr.replaceAll('_limit', '').toUpperCase()} ${ord.volumeInitial}',
          width: 1, dashed: true, fontSize: 10, alignEnd: true,
        ));
      }
    }
    return bands;
  }

  PlotBand _line(double price, Color color, String text,
      {double width = 2, bool dashed = false, double fontSize = 10, bool alignEnd = false}) {
    return PlotBand(
      start: price, end: price, borderColor: color, borderWidth: width,
      dashArray: dashed ? const <double>[5, 5] : [], text: text,
      textStyle: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.bold),
      horizontalTextAlignment: alignEnd ? TextAnchor.end : TextAnchor.start,
      verticalTextAlignment: TextAnchor.end,
    );
  }

  Widget _chart() {
    OpenPosition? selectedPos;
    if (_selectedTicket != null) {
      try { selectedPos = _overlayData.positions.firstWhere((p) => p.ticket == _selectedTicket); } catch(e){}
    }

    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xff0f172a),
            borderRadius: BorderRadius.circular(16),
          ),
          child: SfCartesianChart(
            backgroundColor: const Color(0xff0f172a),
            plotAreaBorderWidth: 0,
            enableAxisAnimation: false,
            zoomPanBehavior: zoomPanBehavior,

            onChartTouchInteractionDown: (ChartTouchInteractionArgs args) {
              if (_ticketActive || _modTarget != null || _chartController == null) return;

              final point = _chartController!.pixelToPoint(args.position);
              if (point.y == null) return;
              final tappedPrice = point.y!.toDouble();

              final tolerance = ((_yMax ?? 0) - (_yMin ?? 0)) * 0.03;

              OpenPosition? nearest;
              double minDiff = double.infinity;

              for (var p in _overlayData.positions) {
                final diff = (p.priceOpen - tappedPrice).abs();
                if (diff < minDiff && diff < tolerance) {
                  minDiff = diff;
                  nearest = p;
                }
              }

              setState(() {
                _selectedTicket = nearest?.ticket;
              });
            },
            onChartTouchInteractionMove: (ChartTouchInteractionArgs args) {
              if (_chartController == null) return;
              final point = _chartController!.pixelToPoint(args.position);
              if (point.y == null) return;

              if (_ticketActive && !_panWhileTicketing) {
                _applyDrag(point.y!.toDouble());
              } else if (_modTarget != null && _selectedTicket != null) {
                setState(() => _modPrice = point.y!.toDouble());
              }
            },

            annotations: <CartesianChartAnnotation>[
              if (selectedPos != null)
                CartesianChartAnnotation(
                  coordinateUnit: CoordinateUnit.point,
                  x: _annotationX,
                  y: _modTarget != null ? _modPrice! : selectedPos.priceOpen,
                  widget: _isModifying
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : _modTarget != null
                      ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTextActionBox("Cancel", Colors.grey, _cancelMod),
                      _buildTextActionBox("Confirm", Colors.blueAccent, _submitMod),
                    ],
                  )
                      : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTextActionBox("X", Colors.redAccent, () => _closePosition(selectedPos!.ticket)),
                      _buildTextActionBox("SL", Colors.orange, () => _startMod(selectedPos!, 'sl')),
                      _buildTextActionBox("TP", Colors.green, () => _startMod(selectedPos!, 'tp')),
                    ],
                  ),
                )
            ],

            // loadMoreIndicatorBuilder completely REMOVED
            primaryXAxis: DateTimeCategoryAxis(
              onRendererCreated: (ChartAxisController controller) => _xAxisController = controller,
              rangePadding: ChartRangePadding.none,
              majorGridLines: const MajorGridLines(width: 0),
              axisLine: const AxisLine(width: 0),
              labelStyle: const TextStyle(color: Colors.grey),
            ),
            primaryYAxis: NumericAxis(
              opposedPosition: true,
              minimum: _yMin,
              maximum: _yMax,
              majorGridLines: const MajorGridLines(width: 0.3, color: Colors.white12),
              axisLine: const AxisLine(width: 0),
              labelStyle: const TextStyle(color: Colors.grey),
              axisLabelFormatter: (AxisLabelRenderDetails details) {
                return ChartAxisLabel(details.value.toStringAsFixed(5), details.textStyle);
              },
              plotBands: _buildPlotBands(),
            ),
            series: <CartesianSeries<dynamic, DateTime>>[
              CandleSeries<Candle, DateTime>(
                onRendererCreated: (c) => _chartController = c,
                animationDuration: 0,
                dataSource: candles,
                xValueMapper: (c, _) => c.time,
                lowValueMapper: (c, _) => c.low,
                highValueMapper: (c, _) => c.high,
                openValueMapper: (c, _) => c.open,
                closeValueMapper: (c, _) => c.close,
                bullColor: Colors.green,
                bearColor: Colors.red,
              ),
              ScatterSeries<ConcludedDeal, DateTime>(
                dataSource: _buyDeals,
                xValueMapper: (d, _) => _snapToCandle(d.time),
                yValueMapper: (d, _) => d.price,
                markerSettings: const MarkerSettings(
                  shape: DataMarkerType.triangle,
                  width: 12, height: 12,
                  color: Colors.blue,
                  borderColor: Colors.white, borderWidth: 1,
                ),
                animationDuration: 0,
              ),
              ScatterSeries<ConcludedDeal, DateTime>(
                dataSource: _sellDeals,
                xValueMapper: (d, _) => _snapToCandle(d.time),
                yValueMapper: (d, _) => d.price,
                markerSettings: const MarkerSettings(
                  shape: DataMarkerType.invertedTriangle,
                  width: 12, height: 12,
                  color: Colors.red,
                  borderColor: Colors.white, borderWidth: 1,
                ),
                animationDuration: 0,
              ),
            ],
          ),
        ),

        // ── MANUAL "LOAD MORE" BUTTON OVERLAY ──
        if (!hasReachedEnd && !_ticketActive && _modTarget == null)
          Positioned(
            top: 20,
            left: 20,
            child: isFetching
                ? Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xff162033).withValues(alpha: 0.9),
                shape: BoxShape.circle,
              ),
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
                : IconButton(
              onPressed: _fetchMore,
              icon: const Icon(Icons.keyboard_arrow_left, color: Colors.white, size: 28),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xff162033).withValues(alpha: 0.9),
                padding: const EdgeInsets.all(10),
              ),
              tooltip: "Load history",
            ),
          ),

        // ── Y-AXIS DRAG OVERLAY (Right Edge) ──
        Positioned(
          right: 10, top: 30, bottom: 40, width: 60,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragUpdate: (details) {
              if (_yMin == null || _yMax == null || _modTarget != null || _ticketActive) return;
              setState(() {
                _autoScaleY = false;
                final dy = details.delta.dy;
                final range = _yMax! - _yMin!;
                final factor = 1.0 + (dy / 200);
                final mid = (_yMax! + _yMin!) / 2;
                final newRange = range * factor;
                _yMax = mid + newRange / 2;
                _yMin = mid - newRange / 2;
              });
            },
            onDoubleTap: () {
              setState(() => _autoScaleY = true);
              _updateYRange();
            },
          ),
        ),

        // ── X-AXIS DRAG OVERLAY (Bottom Edge) ──
        Positioned(
          left: 10, right: 70, bottom: 10, height: 40,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: (details) {
              if (_xAxisController == null || _modTarget != null || _ticketActive) return;

              double currentFactor = _xAxisController!.zoomFactor;
              double currentPosition = _xAxisController!.zoomPosition;

              double delta = details.delta.dx / 200.0;
              double newFactor = (currentFactor + delta).clamp(0.01, 1.0);
              double currentCenter = currentPosition + (currentFactor / 2);
              double newPosition = currentCenter - (newFactor / 2);
              newPosition = newPosition.clamp(0.0, 1.0 - newFactor);

              _xAxisController!.zoomFactor = newFactor;
              _xAxisController!.zoomPosition = newPosition;
            },
            onDoubleTap: () {
              if (_xAxisController != null) {
                _xAxisController!.zoomFactor = 1.0;
                _xAxisController!.zoomPosition = 0.0;
              }
            },
          ),
        ),

        if (_ticketActive && !_panWhileTicketing)
          Positioned(
            top: 20, left: 20, right: 20,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xff162033).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blueAccent),
              ),
              child: Text(
                "Dragging ${_dragTarget.name.toUpperCase()} — drag on chart to set price",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}