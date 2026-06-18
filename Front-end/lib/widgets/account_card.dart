import 'package:flutter/material.dart';
import '../models/account.dart';

class AccountCard extends StatelessWidget {
  final AccountData? data;

  const AccountCard({super.key, this.data});

  @override
  Widget build(BuildContext context) {
    if (data == null) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xff162033),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Balance", style: TextStyle(color: Colors.grey, fontSize: 12)),
          Text("${data!.balance.toStringAsFixed(2)} ${data!.currency}",
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStat("Equity", data!.equity.toStringAsFixed(2)),
              _buildStat("Margin", data!.margin.toStringAsFixed(2)),
              _buildStat("Level", "${data!.marginLevel.toStringAsFixed(0)}%"),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ],
    );
  }
}