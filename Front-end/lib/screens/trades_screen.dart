import 'dart:async';
import 'package:flutter/material.dart';

import '../models/account.dart';
import '../models/position.dart';
import '../models/pending_order.dart';
import '../models/trade_history.dart';
import '../services/api_client.dart';
import '../services/trade_service.dart';
import '../widgets/account_card.dart';

class TradesScreen extends StatefulWidget {
  const TradesScreen({super.key});

  @override
  State<TradesScreen> createState() => _TradesScreenState();
}

class _TradesScreenState extends State<TradesScreen> {
  AccountData? account;
  List<Position> positions = [];
  List<PendingOrder> orders = [];
  List<TradeHistory> history = [];

  bool _isLoading = true;
  bool _isFetching = false; // Prevents overlapping requests
  String? _error;

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Initial fetch with the loading spinner
    _fetchData(showLoading: true);
    _startPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _timer?.cancel();
    // Polls the backend every 2 seconds for near real-time updates
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || _isFetching) return;
      _fetchData(showLoading: false); // Silent background fetch
    });
  }

  Future<void> _fetchData({bool showLoading = true}) async {
    if (_isFetching) return;
    _isFetching = true;

    if (showLoading) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait([
        ApiClient.get('/accounts/info/').catchError((e) {
          debugPrint("Account fetch failed: $e");
          return null;
        }),
        ApiClient.get('/execution/trading-data/').catchError((e) {
          debugPrint("Trading data fetch failed: $e");
          return null;
        }),
      ]);

      if (!mounted) return;

      setState(() {
        if (results[0] != null) {
          account = AccountData.fromJson(results[0]);
        }

        if (results[1] != null) {
          final tradeData = results[1] as Map<String, dynamic>;

          // Parse Positions
          final rawPositions = tradeData['positions'] as List? ?? [];
          positions = rawPositions
              .map((p) => Position.fromJson(p as Map<String, dynamic>))
              .toList();

          // Parse Pending Orders
          final rawOrders = tradeData['orders'] as List? ?? [];
          orders = rawOrders
              .map((o) => PendingOrder.fromJson(o as Map<String, dynamic>))
              .toList();

          // Parse & Sort History (Descending based on timestamp string)
          final rawDeals = tradeData['deals'] as List? ?? [];
          history = rawDeals
              .map((h) => TradeHistory.fromJson(h as Map<String, dynamic>))
              .toList();
          history.sort((a, b) => b.closedAt.compareTo(a.closedAt));
        }
      });

      if (account == null &&
          positions.isEmpty &&
          history.isEmpty &&
          orders.isEmpty) {
        if (showLoading) {
          _error = "Failed to connect to server. Swipe down to retry.";
        }
      } else {
        _error = null; // Clear error if a background fetch succeeds
      }
    } catch (e) {
      if (!mounted) return;
      if (showLoading) setState(() => _error = "Unexpected error: $e");
    } finally {
      _isFetching = false;
      if (mounted && showLoading) setState(() => _isLoading = false);
    }
  }

  // --- API Action Handlers ---

  Future<void> _closePosition(int ticket) async {
    try {
      await TradeService.closePosition(ticket);
      _fetchData(showLoading: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to close position: $e"),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _cancelOrder(int ticket) async {
    try {
      await TradeService.cancelOrder(ticket);
      _fetchData(showLoading: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to cancel order: $e"),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => _fetchData(showLoading: true),
        color: Colors.blueAccent,
        backgroundColor: const Color(0xff162033),
        child: _isLoading && account == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                      const SizedBox(height: 15),
                    ],

                    AccountCard(data: account, history: []),

                    const SizedBox(height: 20),
                    _sectionTitle("Open Positions"),
                    if (positions.isEmpty && !_isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          "No open positions",
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      _positions(),

                    const SizedBox(height: 20),
                    _sectionTitle("Pending Orders"),
                    if (orders.isEmpty && !_isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          "No pending orders",
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      _orders(),

                    const SizedBox(height: 20),
                    _sectionTitle("Trade History"),
                    if (history.isEmpty && !_isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          "No trade history",
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      _history(),
                  ],
                ),
              ),
      ),
    );
  }

  // ---------------- POSITIONS ----------------

  Widget _positions() {
    return Column(
      children: positions.map((p) {
        final isBuy = p.type.toUpperCase() == "BUY";

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.only(
            left: 12,
            top: 12,
            bottom: 12,
            right: 4,
          ),
          decoration: BoxDecoration(
            color: const Color(0xff111827),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.pair,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: (isBuy ? Colors.green : Colors.red)
                                .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            "${p.type.toUpperCase()} ${p.lot}",
                            style: TextStyle(
                              color: isBuy ? Colors.green : Colors.redAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          "Entry: ${p.entry}",
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "Now: ${p.current}",
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                children: [
                  Text(
                    "${p.profit > 0 ? '+' : ''}${p.profit.toStringAsFixed(2)}",
                    style: TextStyle(
                      color: p.profit > 0
                          ? Colors.green
                          : (p.profit < 0 ? Colors.red : Colors.white),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                    onPressed: () => _closePosition(p.ticket),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ---------------- PENDING ORDERS ----------------

  Widget _orders() {
    return Column(
      children: orders.map((o) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.only(
            left: 12,
            top: 12,
            bottom: 12,
            right: 4,
          ),
          decoration: BoxDecoration(
            color: const Color(0xff111827),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          o.symbol,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            "${o.type} ${o.volume}",
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          "Target",
                          style: TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          o.price.toStringAsFixed(5),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                onPressed: () => _cancelOrder(o.ticket),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(8),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ---------------- HISTORY ----------------

  Widget _history() {
    return Column(
      children: history.map((h) {
        final isBuy = h.type.toUpperCase() == "BUY";

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xff111827),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    h.pair,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    h.type.toUpperCase(),
                    style: TextStyle(
                      color: isBuy ? Colors.blueAccent : Colors.redAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    h.closedAt,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${h.profit > 0 ? '+' : ''}${h.profit.toStringAsFixed(2)}",
                    style: TextStyle(
                      color: h.profit > 0
                          ? Colors.green
                          : (h.profit < 0 ? Colors.red : Colors.white),
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ---------------- HELPERS ----------------

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
