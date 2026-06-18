import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../models/candle.dart';
import '../models/trading_data.dart';
import '../services/market_service.dart';
import '../services/api_client.dart';

class FullscreenChartScreen extends StatefulWidget {
  final String symbol;
  final String timeframe;

  const FullscreenChartScreen({
    super.key,
    required this.symbol,
    required this.timeframe,
  });

  @override
  State<FullscreenChartScreen> createState() => _FullscreenChartScreenState();
}

class _FullscreenChartScreenState extends State<FullscreenChartScreen> {
  final MarketService marketService = MarketService();
  ChartSeriesController? _chartController;

  List<Candle> candles = [];
  bool loading = false;

  // State variables for infinite scroll
  bool isFetching = false;
  bool hasReachedEnd = false;
  DateTime? lastFetchTime;

  // --- OVERLAY DATA STATE ---
  TradingOverlayData _overlayData = TradingOverlayData.empty();

  Timer? _timer;
  late ZoomPanBehavior zoomPanBehavior;

  @override
  void initState() {
    super.initState();

    // Set landscape
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

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

    // Reset to portrait
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  // Fetches live metadata, limits, and historical indicators
  Future<void> _fetchTradingOverlayData() async {
    try {
      final response = await ApiClient.get(
        '/execution/trading-data/?symbol=${widget.symbol}',
      );

      if (response != null && mounted) {
        setState(() {
          _overlayData = TradingOverlayData.fromJson(response);
        });
      }
    } catch (e) {
      debugPrint("Error loading overlay metrics: $e");
    }
  }

  Future<void> fetchCandles() async {
    setState(() {
      loading = true;
      hasReachedEnd = false;
    });

    try {
      final result = await marketService.getCandles(
        symbol: widget.symbol,
        timeframe: widget.timeframe,
        count: 100,
      );

      if (!mounted) return;

      setState(() {
        candles = result;
      });

      _startPolling();
    } catch (e) {
      debugPrint("fullscreen fetch error: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> loadMoreCandles() async {
    final now = DateTime.now();
    final isTooSoon =
        lastFetchTime != null &&
        now.difference(lastFetchTime!) < const Duration(seconds: 1);

    if (isFetching || hasReachedEnd || isTooSoon || candles.isEmpty) {
      return;
    }

    setState(() => isFetching = true);
    lastFetchTime = now;

    try {
      final older = await marketService.getCandles(
        symbol: widget.symbol,
        timeframe: widget.timeframe,
        count: 100,
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
      debugPrint("load more error: $e");
    } finally {
      if (mounted) setState(() => isFetching = false);
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || candles.isEmpty) return;

      _fetchTradingOverlayData();

      try {
        final result = await marketService.getCandles(
          symbol: widget.symbol,
          timeframe: widget.timeframe,
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

  // Filter deals based on currently visible candle range
  List<ConcludedDeal> _getVisibleDeals(String entryType) {
    if (candles.isEmpty) return [];
    final startTime = candles.first.time;
    final endTime = candles.last.time;

    return _overlayData.deals.where((deal) {
      return deal.entryStr == entryType &&
          deal.time.isAfter(startTime.subtract(const Duration(seconds: 1))) &&
          deal.time.isBefore(endTime.add(const Duration(seconds: 1)));
    }).toList();
  }

  List<PlotBand> _buildPlotBands() {
    final List<PlotBand> bands = [];

    // 1. Active Open Positions
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

    // 2. Pending Limit Orders
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff0f172a),
      appBar: AppBar(
        backgroundColor: const Color(0xff0f172a),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "${widget.symbol} (${widget.timeframe})",
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _chart(),
    );
  }

  Widget _chart() {
    return SfCartesianChart(
      backgroundColor: const Color(0xff0f172a),
      plotAreaBorderWidth: 0,
      enableAxisAnimation: false,
      zoomPanBehavior: zoomPanBehavior,

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
              } else {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => loadMoreCandles(),
                );
                return const SizedBox.shrink();
              }
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
        plotBands: _buildPlotBands(),
      ),
      series: <CartesianSeries<dynamic, DateTime>>[
        // Candle Series
        CandleSeries(
          animationDuration: 0,
          onRendererCreated: (ChartSeriesController controller) {
            _chartController = controller;
          },
          dataSource: candles,
          xValueMapper: (c, _) => c.time,
          lowValueMapper: (c, _) => c.low,
          highValueMapper: (c, _) => c.high,
          openValueMapper: (c, _) => c.open,
          closeValueMapper: (c, _) => c.close,
          bullColor: Colors.green,
          bearColor: Colors.red,
        ),

        // Concluded Entries
        ScatterSeries<ConcludedDeal, DateTime>(
          dataSource: _getVisibleDeals('in'),
          xValueMapper: (d, _) => d.time,
          yValueMapper: (d, _) => d.price,
          markerSettings: const MarkerSettings(
            shape: DataMarkerType.triangle,
            width: 11,
            height: 11,
            color: Colors.blueAccent,
            borderColor: Colors.white,
            borderWidth: 1,
          ),
          animationDuration: 0,
        ),

        // Concluded Exits
        ScatterSeries<ConcludedDeal, DateTime>(
          dataSource: _getVisibleDeals('out'),
          xValueMapper: (d, _) => d.time,
          yValueMapper: (d, _) => d.price,
          markerSettings: const MarkerSettings(
            shape: DataMarkerType.diamond,
            width: 11,
            height: 11,
            color: Colors.purpleAccent,
            borderColor: Colors.white,
            borderWidth: 1,
          ),
          animationDuration: 0,
        ),
      ],
    );
  }
}
