import 'package:flutter/material.dart';

class StrategyScreen extends StatefulWidget {
  const StrategyScreen({super.key});

  @override
  State<StrategyScreen> createState() => _StrategyScreenState();
}

class _StrategyScreenState extends State<StrategyScreen> {
  int? expandedIndex;

  final strategies = [
    {
      "name": "TwoHunters",
      "status": "RUNNING",
      "margin_pips": 0.1,
      "fvg": {"min": 5.0, "max": 10.0},
      "ratios": {"sl": 1.0, "tp": 2.0},
      "breakout": {"main": 2, "recovery": 1},
      "sessions": {"london": "13:30-17:29", "ny": "18:30-00:29"},
      "flags": {"risk_manager": false, "trend_flag": false},
    },
    {
      "name": "Tweny",
      "status": "STOPPED",
      "sl": 1,
      "tp": 4,
      "force_stop_time": "17:30",
    },
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: strategies.length,
        itemBuilder: (context, index) {
          final s = strategies[index];
          final isExpanded = expandedIndex == index;

          return GestureDetector(
            onTap: () {
              setState(() {
                expandedIndex = isExpanded ? null : index;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xff162033),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(s),

                  if (isExpanded) ...[
                    const SizedBox(height: 15),
                    _buildConfig(s),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _header(Map s) {
    final running = s["status"] == "RUNNING";

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          s["name"],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),

        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: running ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              s["status"],
              style: TextStyle(color: running ? Colors.green : Colors.red),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildConfig(Map s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row("Margin Pips", s["margin_pips"]),

        const SizedBox(height: 8),

        _section("FVG"),
        _row("Min", s["fvg"]?["min"]),
        _row("Max", s["fvg"]?["max"]),

        const SizedBox(height: 8),

        _section("Ratios"),
        _row("SL", s["ratios"]?["sl"]),
        _row("TP", s["ratios"]?["tp"]),

        const SizedBox(height: 8),

        _section("Breakout"),
        _row("Main Hunt", s["breakout"]?["main"]),
        _row("Recovery", s["breakout"]?["recovery"]),

        const SizedBox(height: 8),

        _section("Sessions"),
        _text("London: ${s["sessions"]?["london"]}"),
        _text("NY: ${s["sessions"]?["ny"]}"),
      ],
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.green,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _row(String label, dynamic value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Text(value.toString(), style: const TextStyle(color: Colors.white)),
      ],
    );
  }

  Widget _text(String t) {
    return Text(t, style: const TextStyle(color: Colors.white));
  }
}
