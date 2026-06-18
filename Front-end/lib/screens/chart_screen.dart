import 'dart:async';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../models/candle.dart';
import '../models/trading_data.dart';
import '../services/market_service.dart';
import '../widgets/trade_dialog.dart';
import 'fullscreen_chart_screen.dart';
import '../services/api_client.dart';


class ChartScreen extends StatefulWidget {
  const ChartScreen({super.key});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  final MarketService marketService = MarketService();

  ChartSeriesController? _chartController;

  final TextEditingController _symbolController = TextEditingController(
    text: "EURUSD",
  );
  final List<String> timeframes = ["M1", "M5", "M15", "H1", "H4", "D1"];
  String selectedTimeframe = "M1";
  List<Candle> candles = [];
  bool loading = false;
  DateTime? lastFetchTime;
  bool isFetching = false;
  bool hasReachedEnd = false;
  TradingOverlayData _overlayData = TradingOverlayData.empty();
  bool _isPlacingOrder = false;
  String _pendingSide = 'buy_limit';
  double _pendingVolume = 0.01;
  double _pendingPrice = 0.0;
  bool _isSubmittingOrder = false;
  Timer? _timer;
  late ZoomPanBehavior zoomPanBehavior;

  @override
  void initState() {
    super.initState();
    zoomPanBehavior = ZoomPanBehavior(
      enablePinching: true,
      enablePanning: true,
      zoomMode: ZoomMode.xy,
    );
    fetchCandles();
    _fetchTradingOverlayData();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _symbolController.dispose();
    super.dispose();
  }

  String get symbol => _symbolController.text.trim();

  Future<void> _fetchTradingOverlayData() async {
    try {
      final response = await ApiClient.get('/execution/trading-data/?symbol=$symbol');

      if (response != null) {
        setState(() {
          _overlayData = TradingOverlayData.fromJson(response);
        });
      }
    } catch (e) {
      debugPrint("Error loading overlay metrics: $e");
    }
  }

  List<ConcludedDeal> _getVisibleDeals(String entryType) {
    if (candles.isEmpty) return [];

    final DateTime startTime = candles.first.time;
    final DateTime endTime = candles.last.time;

    return _overlayData.deals.where((deal) {
      final bool isCorrectType = deal.entryStr == entryType;

      final bool isInRange =
          !deal.time.isBefore(
            startTime.subtract(const Duration(seconds: 1)),
          ) &&
              !deal.time.isAfter(
                endTime.add(const Duration(seconds: 1)),
              );

      return isCorrectType && isInRange;
    }).toList();
  }

  Future<void> _fetchMore() async {
    final now = DateTime.now();

    final isTooSoon =
        lastFetchTime != null &&
        now.difference(lastFetchTime!) < const Duration(seconds: 1);
    if (isFetching || hasReachedEnd || isTooSoon) {
      return;
    }

    setState(() => isFetching = true);
    lastFetchTime = now;

    try {
      final older = await marketService.getCandles(
        symbol: symbol,
        timeframe: selectedTimeframe,
        count: 60,
        before: candles.first.time,
      );

      if (!mounted) return;

      if (older.isEmpty) {
        setState(() => hasReachedEnd = true);
        return;
      }

      if (older.last.time.isAtSameMomentAs(candles.first.time)) {
        older.removeLast();
      }

      if (older.isNotEmpty) {
        setState(() {
          candles.insertAll(0, older);
        });
      } else {
        setState(() => hasReachedEnd = true);
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      setState(() => isFetching = false);
    }
  }

  Future<void> fetchCandles() async {
    setState(() {
      loading = true;
      hasReachedEnd = false;
    });

    try {
      final result = await marketService.getCandles(
        symbol: symbol,
        timeframe: selectedTimeframe,
        count: 60,
      );
      setState(() {
        candles = result;
      });
      _startPolling();
    } catch (e) {
      debugPrint("fetch error: $e");
    }
    setState(() => loading = false);
  }

  void _startPolling() {
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || candles.isEmpty) return;
      _fetchTradingOverlayData();
      try {
        final result = await marketService.getCandles(
          symbol: symbol,
          timeframe: selectedTimeframe,
          count: 1,
        );
        if (result.isEmpty) return;
        final newCandle = result.last;
        final lastIndex = candles.length - 1;
        if (candles[lastIndex].time == newCandle.time) {
          candles[lastIndex] = newCandle;
          _chartController?.updateDataSource(updatedDataIndexes: [lastIndex]);
        } else {
          candles.add(newCandle);
          _chartController?.updateDataSource(
            addedDataIndexes: [candles.length - 1],
          );
        }
      } catch (e) {
        debugPrint("poll error: $e");
      }
    });
  }

  void openFullscreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            FullscreenChartScreen(symbol: symbol, timeframe: selectedTimeframe),
      ),
    );
  }

  Future<void> _startVisualOrderPlacement() async {
    String tempSide = 'buy_limit';

    final TextEditingController volumeController = TextEditingController(
      text: "0.01",
    );

    final result = await showDialog<bool>(
      context: context,

      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xff162033),
              title: Text(
                "Setup Pending Order - $symbol",
                style: const TextStyle(color: Colors.white),
              ),

              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: tempSide,
                    dropdownColor: const Color(0xff162033),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Side",
                      labelStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xff0f172a),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),

                    items: const [
                      DropdownMenuItem(
                        value: 'buy_limit',
                        child: Text("Buy Limit"),
                      ),

                      DropdownMenuItem(
                        value: 'sell_limit',
                        child: Text("Sell Limit"),
                      ),
                    ],

                    onChanged: (v) => setDialogState(() => tempSide = v!),
                  ),

                  const SizedBox(height: 10),

                  TextField(
                    controller: volumeController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: "Volume",
                      labelStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xff0f172a),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),

              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),

                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text(
                    "Place on Chart",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      setState(() {
        _pendingSide = tempSide;
        _pendingVolume = double.tryParse(volumeController.text) ?? 0.01;
        _pendingPrice = candles.isNotEmpty ? candles.last.close : 1.0;
        _isPlacingOrder = true;
        zoomPanBehavior = ZoomPanBehavior(
          enablePanning: false,
          enablePinching: false,
          zoomMode: ZoomMode.xy,
        );
      });
    }
  }

  Future<void> _submitVisualOrder() async {
    setState(() => _isSubmittingOrder = true);

    try {
      final payload = {
        "symbol": symbol,
        "volume": _pendingVolume,
        "order_type": _pendingSide,
        "price": _pendingPrice,
      };

      await ApiClient.post('/execution/order/', body: payload);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Order placed successfully!"),
          backgroundColor: Colors.green,
        ),
      );

      _fetchTradingOverlayData();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Order failed: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingOrder = false;
          _isPlacingOrder = false;
          zoomPanBehavior = ZoomPanBehavior(
            enablePanning: true,
            enablePinching: true,
            zoomMode: ZoomMode.xy,
          );
        });
      }
    }
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

          _tradeControls(),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.all(10),

      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: TextField(
              controller: _symbolController,
              onSubmitted: (_) {
                fetchCandles();
                _fetchTradingOverlayData();
              },
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
                fetchCandles();
              },
            ),
          ),

          const Spacer(),
          IconButton(
            onPressed: () {
              fetchCandles();
              _fetchTradingOverlayData();
            },
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
            child: _styledButton(
              "Open Position",
              const Color(0xff162033),
              () => showDialog(
                context: context,
                builder: (_) => TradeDialog(symbol: symbol, isPending: false),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _styledButton(
              "Set Order",
              const Color(0xff162033),
              _startVisualOrderPlacement,
            ),
          ),
        ],
      ),
    );
  }

  Widget _styledButton(String text, Color color, VoidCallback onPressed) {
    return SizedBox(
      height: 45,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onPressed,
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _chartOverlay() {
    if (!_isPlacingOrder) return const SizedBox.shrink();

    return Positioned(
      top: 20,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xff162033).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blueAccent),
        ),

        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                "Drag line to set price. \nVol: $_pendingVolume",
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),

            TextButton(
              onPressed: () {
                setState(() {
                  _isPlacingOrder = false;
                  zoomPanBehavior = ZoomPanBehavior(
                    enablePanning: true,
                    enablePinching: true,
                    zoomMode: ZoomMode.xy,
                  );
                });
              },

              child: const Text(
                "Cancel",
                style: TextStyle(color: Colors.redAccent),
              ),
            ),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
              ),
              onPressed: _isSubmittingOrder ? null : _submitVisualOrder,
              child: _isSubmittingOrder
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      "Confirm",
                      style: TextStyle(color: Colors.white),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<PlotBand> _buildPlotBands() {
    final List<PlotBand> bands = [];

    // 1. Drag-to-place line
    if (_isPlacingOrder) {
      bands.add(
        PlotBand(
          start: _pendingPrice,
          end: _pendingPrice,
          borderColor: _pendingSide.contains('buy') ? Colors.green : Colors.red,
          borderWidth: 2,
          dashArray: const <double>[5, 5],
          text:
              '${_pendingSide.toUpperCase()}: ${_pendingPrice.toStringAsFixed(5)}',
          textStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          horizontalTextAlignment: TextAnchor.start,
          verticalTextAlignment: TextAnchor.end,
        ),
      );
    }

    // 2. Active Open Positions
    for (var pos in _overlayData.positions) {
      final isBuy = pos.typeStr.toLowerCase() == 'buy';

      bands.add(
        PlotBand(
          start: pos.priceOpen,
          end: pos.priceOpen,
          borderColor: isBuy ? Colors.greenAccent : Colors.redAccent,
          borderWidth: 1.5,
          text:
              'POS #${pos.ticket} ${pos.typeStr.toUpperCase()} ${pos.volume} @ ${pos.priceOpen.toStringAsFixed(5)}',
          textStyle: TextStyle(
            color: isBuy ? Colors.greenAccent : Colors.redAccent,
            fontSize: 10,
          ),
          horizontalTextAlignment: TextAnchor.start,
          verticalTextAlignment: TextAnchor.end,
        ),
      );
    }

    // 3. Pending Limit Orders
    for (var ord in _overlayData.orders) {
      bands.add(
        PlotBand(
          start: ord.priceOpen,
          end: ord.priceOpen,
          borderColor: Colors.amber,
          borderWidth: 1.0,
          dashArray: const <double>[3, 3],
          text:
              'LIMIT #${ord.ticket} ${ord.typeStr.replaceAll('_limit', '').toUpperCase()} ${ord.volumeInitial}',
          textStyle: const TextStyle(color: Colors.amber, fontSize: 10),
          horizontalTextAlignment: TextAnchor.end,
          verticalTextAlignment: TextAnchor.end,
        ),
      );
    }
    return bands;
  }

  Widget _chart() {
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
            onChartTouchInteractionMove: (ChartTouchInteractionArgs args) {
              if (_isPlacingOrder && _chartController != null) {
                final ChartPoint<dynamic> point = _chartController!
                    .pixelToPoint(args.position);
                setState(() {
                  _pendingPrice = point.y!.toDouble();
                });
              }
            },

            loadMoreIndicatorBuilder:
                (BuildContext context, ChartSwipeDirection direction) {
                  if (direction == ChartSwipeDirection.start) {
                    if (isFetching) {
                      return const SizedBox(
                        width: 50,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      );
                    }
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _fetchMore(),
                    );
                    return const SizedBox.shrink();
                  }
                  return const SizedBox.shrink();
                },

            primaryXAxis: DateTimeAxis(
              majorGridLines: const MajorGridLines(width: 0),
              axisLine: const AxisLine(width: 0),
              labelStyle: const TextStyle(color: Colors.grey),
            ),

            primaryYAxis: NumericAxis(
              opposedPosition: true,
              majorGridLines: const MajorGridLines(width: 0),
              axisLine: const AxisLine(width: 0),
              labelStyle: const TextStyle(color: Colors.grey),
              plotBands:
                  _buildPlotBands(), // Displays open positions and limit bands
            ),

            series: <CartesianSeries<dynamic, DateTime>>[
              // Base Candlesticks
              CandleSeries<Candle, DateTime>(
                onRendererCreated: (ChartSeriesController controller) {
                  _chartController = controller;
                },
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

              LineSeries<ConcludedDeal, DateTime>(
                dataSource: _getVisibleDeals('in'),
                xValueMapper: (d, _) => d.time,
                yValueMapper: (d, _) => d.price,
                color: Colors.transparent,
                markerSettings: const MarkerSettings(
                  isVisible: true,
                  shape: DataMarkerType.triangle,
                  width: 12,
                  height: 12,
                  color: Colors.blue,
                  borderColor: Colors.white,
                  borderWidth: 2,
                ),
                animationDuration: 0,
              ),

              LineSeries<ConcludedDeal, DateTime>(
                dataSource: _getVisibleDeals('out'),
                xValueMapper: (d, _) => d.time,
                yValueMapper: (d, _) => d.price,
                color: Colors.transparent,
                markerSettings: const MarkerSettings(
                  isVisible: true,
                  shape: DataMarkerType.triangle,
                  width: 12,
                  height: 12,
                  color: Colors.red,
                  borderColor: Colors.white,
                  borderWidth: 2,
                ),
                animationDuration: 0,
              ),
            ],
          ),
        ),

        Positioned(
          bottom: 16,
          right: 16,
          child: GestureDetector(
            onTap: openFullscreen,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xff1f2937),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.fullscreen, color: Colors.white),
            ),
          ),
        ),

        _chartOverlay(),
      ],
    );
  }
}

