import 'package:flutter/material.dart';
import '../models/account.dart';
import '../models/trade_history.dart';

class AccountCard extends StatelessWidget {
  final AccountData? data;
  final List<TradeHistory> history;

  const AccountCard({super.key, this.data, this.history = const []});

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final d = data!;

    // 1. Calculate Financials
    final double totalRealizedPnL = history.fold(
      0.0,
          (sum, h) => sum + h.profit,
    );

    final double usagePercent = d.equity > 0
        ? (d.margin / d.equity) * 100
        : 0.0;

    // 2. PnL Styling
    final double floatingPl = d.equity - d.balance;
    final bool plPositive = floatingPl >= 0;
    final Color plColor = plPositive ? Colors.green : Colors.redAccent;

    // 3. Card Background Styling based on margin usage
    final bool isWarning = usagePercent >= 70;
    final List<Color> cardGradient = isWarning
        ? const [Color(0xff3a1c1c), Color(0xff241212)] // Red warning shade
        : const [Color(0xff1b2740), Color(0xff141d30)]; // Default blue/navy shade

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: cardGradient,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          // Hero Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "EQUITY",
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    d.equity.toStringAsFixed(2),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: plColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${plPositive ? '+' : ''}${floatingPl.toStringAsFixed(2)}',
                  style: TextStyle(color: plColor, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Grid Section
          Row(
            children: [
              Expanded(
                child: _stat(
                  "Balance",
                  d.balance.toStringAsFixed(2),
                  Icons.account_balance_wallet,
                  Colors.blueAccent,
                ),
              ),
              Expanded(
                child: _stat(
                  "Total PnL",
                  totalRealizedPnL.toStringAsFixed(2),
                  Icons.show_chart,
                  totalRealizedPnL >= 0 ? Colors.greenAccent : Colors.redAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _stat(
                  "Free Margin",
                  d.freeMargin.toStringAsFixed(2),
                  Icons.account_balance_wallet_outlined,
                  Colors.greenAccent,
                ),
              ),
              Expanded(
                child: _stat(
                  "Leverage",
                  "1:${d.leverage.toInt()}",
                  Icons.speed,
                  Colors.white70,
                ),
              ),
            ],
          ),

          // Margin Used Bar
          const SizedBox(height: 20),
          _marginBar(usagePercent),
        ],
      ),
    );
  }

  Color _usageColor(double usage) {
    if (usage < 30) return Colors.greenAccent;
    if (usage < 70) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  Widget _marginBar(double usagePercent) {
    final frac = (usagePercent / 100).clamp(0.0, 1.0);
    final color = _usageColor(usagePercent);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Margin Used",
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            Text(
              "${usagePercent.toStringAsFixed(1)}%",
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: frac,
            minHeight: 6,
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _stat(String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}