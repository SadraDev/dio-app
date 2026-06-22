import 'package:flutter/material.dart';

import '../models/strategy_state.dart';
import '../services/strategy_service.dart';
import '../widgets/strategy_card.dart';
import 'two_hunters_screen.dart';

/// Strategy hub:
///   * top: tappable strategy cards (TwoHunters -> detail; Tweny placeholder)
///   * bottom: live "active" worker cards with pause / resume / kill
class StrategyScreen extends StatelessWidget {
  final StrategyService strategy;
  const StrategyScreen({super.key, required this.strategy});

  Future<void> _confirmKill(BuildContext context, WorkerState w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xff162033),
        title: const Text('Kill strategy?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Kill ${w.strategy} on ${w.symbol}? The worker stops permanently and '
          'is removed from the list.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kill', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) strategy.kill(w.key);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('Strategies'),
            _strategyTile(
              context,
              name: 'TwoHunters',
              subtitle: 'MBox breakout hunter • default breakout + backtest',
              enabled: true,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => TwoHuntersScreen(strategy: strategy)),
              ),
            ),
            _strategyTile(
              context,
              name: 'Tweny',
              subtitle: 'Not yet wired to the backend',
              enabled: false,
              onTap: () {},
            ),

            const SizedBox(height: 8),
            _title('Active'),
            StreamBuilder<List<WorkerState>>(
              stream: strategy.states,
              initialData: strategy.snapshot,
              builder: (context, snap) {
                final workers = snap.data ?? [];
                if (workers.isEmpty) {
                  return _placeholder(
                      'No running strategies. Open TwoHunters to start one.');
                }
                return Column(
                  children: workers
                      .map((w) => StrategyCard(
                            state: w,
                            onPause: () => strategy.pause(w.key),
                            onResume: () => strategy.resume(w.key),
                            onKill: () => _confirmKill(context, w),
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _strategyTile(BuildContext context,
      {required String name,
      required String subtitle,
      required bool enabled,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xff162033),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: enabled ? Colors.blueAccent.withValues(alpha: 0.4) : Colors.white12),
        ),
        child: Row(
          children: [
            Icon(Icons.psychology,
                color: enabled ? Colors.blueAccent : Colors.white30, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(
                          color: enabled ? Colors.white : Colors.white54,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            if (enabled)
              const Icon(Icons.chevron_right, color: Colors.white38)
            else
              const Text('Soon',
                  style: TextStyle(color: Colors.white30, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 4),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      );

  Widget _placeholder(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: const Color(0xff162033), borderRadius: BorderRadius.circular(16)),
        child: Text(text, style: const TextStyle(color: Colors.grey)),
      );
}
