import 'package:flutter/material.dart';

import '../models/account.dart';
import '../models/position.dart';
import '../models/trade_history.dart';

class TradesScreen extends StatefulWidget {
  const TradesScreen({super.key});

  @override
  State<TradesScreen> createState() => _TradesScreenState();
}

class _TradesScreenState extends State<TradesScreen> {
  // MOCK DATA (replace with Django API later)

  late AccountData account;
  late List<Position> positions;
  late List<TradeHistory> history;

  @override
  void initState() {
    super.initState();
    _loadMockData();
  }

  void _loadMockData() {
    account = AccountData(
      balance: 10000,
      equity: 10250,
      marginLevel: 2.0,
      margin: 1200,
      freeMargin: 8800,
      currency: '',
    );

    positions = [
      Position(
        pair: "EUR/USD",
        type: "BUY",
        lot: 0.10,
        entry: 1.0850,
        current: 1.0890,
        profit: 40,
      ),
      Position(
        pair: "GBP/USD",
        type: "SELL",
        lot: 0.20,
        entry: 1.2740,
        current: 1.2710,
        profit: 60,
      ),
    ];

    history = [
      TradeHistory(
        pair: "USD/JPY",
        type: "BUY",
        profit: -15,
        closedAt: "2026-06-16",
      ),
      TradeHistory(
        pair: "XAU/USD",
        type: "SELL",
        profit: 120,
        closedAt: "2026-06-15",
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _accountCard(),
            const SizedBox(height: 15),
            _sectionTitle("Open Positions"),
            _positions(),
            const SizedBox(height: 15),
            _sectionTitle("Trade History"),
            _history(),
          ],
        ),
      ),
    );
  }

  // ---------------- ACCOUNT ----------------

  Widget _accountCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xff162033),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Account Summary",
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 15),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _metric("Balance", account.balance),
              _metric("Equity", account.equity),
              _metric(
                "PnL",
                account.margin,
                color: account.margin >= 0 ? Colors.green : Colors.red,
              ),
            ],
          ),

          const SizedBox(height: 15),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _metric("Margin", account.margin),
              _metric("Free", account.freeMargin),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------- POSITIONS ----------------

  Widget _positions() {
    return Column(
      children: positions.map((p) {
        final isBuy = p.type == "BUY";

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
                    p.pair,
                    style: const TextStyle(color: Colors.white),
                  ),
                  Text(
                    "${p.type} ${p.lot}",
                    style: TextStyle(
                      color: isBuy ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),

              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "Entry: ${p.entry}",
                    style: const TextStyle(color: Colors.grey),
                  ),
                  Text(
                    "Now: ${p.current}",
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),

              Text(
                "${p.profit >= 0 ? '+' : ''}${p.profit}",
                style: TextStyle(
                  color: p.profit >= 0 ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
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
                    style: const TextStyle(color: Colors.white),
                  ),
                  Text(
                    h.type,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
              Text(
                "${h.profit >= 0 ? '+' : ''}${h.profit}",
                style: TextStyle(
                  color: h.profit >= 0 ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ---------------- HELPERS ----------------

  Widget _metric(String label, double value, {Color? color}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 5),
        Text(
          value.toString(),
          style: TextStyle(
            color: color ?? Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

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