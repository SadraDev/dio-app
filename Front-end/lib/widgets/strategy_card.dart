import 'package:Dio/services/strategy_service.dart';
import 'package:flutter/material.dart';
import '../models/strategy_state.dart';
import '../models/two_hunters_config.dart';
import 'config_editor.dart';

class StrategyCard extends StatelessWidget {
  final WorkerState state;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onKill;
  final VoidCallback? onTap;

  const StrategyCard({
    super.key,
    required this.state,
    this.onPause,
    this.onResume,
    this.onKill,
    this.onTap,
  });

  Color get _accent {
    if (state.paused) return Colors.orangeAccent;
    if (!state.running) return Colors.grey;
    switch (state.phase) {
      case WorkerPhase.huntingPhase:
        return Colors.amber;
      case WorkerPhase.orderPlaced:
        return Colors.cyanAccent;
      case WorkerPhase.positionPlaced:
      case WorkerPhase.monitoringSignal:
        return Colors.blueAccent;
      case WorkerPhase.done:
        return Colors.greenAccent;
      case WorkerPhase.paused:
        return Colors.orangeAccent;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sig = state.activeSignal;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xff162033),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _accent.withValues(alpha: 0.35), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        state.strategy,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        state.symbol,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                _statusPill(),
              ],
            ),
            const SizedBox(height: 12),

            // Narration line
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 5, right: 8),
                  decoration: BoxDecoration(
                    color: _accent,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    state.message,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),

            // Config summary (what this worker runs with)
            const SizedBox(height: 8),
            _configLine(),

            // In-trade stats
            if (sig != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xff0f172a),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _miniStat(
                          'Side',
                          sig.side,
                          color: sig.side == 'BUY'
                              ? Colors.green
                              : Colors.redAccent,
                        ),
                        _miniStat('Lots', sig.lots.toStringAsFixed(2)),
                        _miniStat('Entry', sig.entry.toStringAsFixed(5)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _miniStat('SL', '${sig.slPips.toStringAsFixed(1)}p'),
                        _miniStat('TP', '${sig.tpPips.toStringAsFixed(1)}p'),
                        _miniStat(
                          'P/L',
                          '${sig.gain >= 0 ? '+' : '-'}\$${sig.gain.abs().toStringAsFixed(2)}',
                          color: sig.gain >= 0
                              ? Colors.green
                              : Colors.redAccent,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: _todayTally()),
                _controls(context),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _configLine() {
    final cfg = state.config;
    double getNum(List<String> path, double def) {
      dynamic n = cfg;
      for (final k in path) {
        if (n is Map && n.containsKey(k)) {
          n = n[k];
        } else {
          return def;
        }
      }
      return (n is num) ? n.toDouble() : def;
    }

    final risk = getNum(['risk_percent'], 0.005) * 100;
    final sl = getNum(['ratios', 'stop_loss'], 1.0);
    final tp = getNum(['ratios', 'take_profit'], 2.0);
    final hunts = getNum(['breakout', 'num_hunt_main'], 2).toInt();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _tag('risk ${risk.toStringAsFixed(2)}%', Colors.white24),
        _tag('SL:TP $sl:$tp', Colors.white24),
        _tag('$hunts hunts', Colors.white24),
      ],
    );
  }

  Widget _tag(String text, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: c == Colors.white24 ? Colors.white70 : c,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _statusPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accent.withValues(alpha: 0.5)),
      ),
      child: Text(
        state.statusLabel,
        style: TextStyle(
          color: _accent,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, {Color color = Colors.white}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _todayTally() {
    final t = state.today;
    return Row(
      children: [_outcomeChip('Today', t.outcome), const SizedBox(width: 10)],
    );
  }

  Widget _outcomeChip(String label, String? outcome) {
    Color c;
    String text;
    switch (outcome) {
      case 'win':
        c = Colors.green;
        text = 'W';
        break;
      case 'loss':
        c = Colors.redAccent;
        text = 'L';
        break;
      case 'force_stoped':
        c = Colors.orangeAccent;
        text = 'F';
        break;
      default:
        c = Colors.white24;
        text = '-';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label $text',
        style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _controls(BuildContext context) {
    final buttons = <Widget>[];

    // --- Add Config Edit Button ---
    buttons.add(
      _ctrlBtn('Config', Icons.settings, Colors.blueAccent, () {
        _showConfigEditor(context);
      }),
    );
    buttons.add(const SizedBox(width: 6));

    if (state.paused) {
      if (onResume != null) {
        buttons.add(
          _ctrlBtn('Resume', Icons.play_circle, Colors.green, onResume!),
        );
      }
    } else if (state.running) {
      if (onPause != null) {
        buttons.add(
          _ctrlBtn('Pause', Icons.pause_circle, Colors.amber, onPause!),
        );
      }
    }
    if (onKill != null) {
      buttons.add(const SizedBox(width: 6));
      buttons.add(
        _ctrlBtn('Kill', Icons.stop_circle, Colors.redAccent, onKill!),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: buttons);
  }

  void _showConfigEditor(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xff111827),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          maxChildSize: 0.9,
          builder: (_, scrollController) => SingleChildScrollView(
            controller: scrollController,
            child: Column(
              children: [
                const Text(
                  "Runtime Configuration",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                TwoHuntersConfigEditor(
                  config: TwoHuntersConfig(
                    Map<String, dynamic>.from(state.config),
                  ),
                  buttonText: "Update Live Worker",
                  onSave: (updatedConfig) async {
                    try {
                      // Execute the API call
                      await StrategyApi.updateWorkerConfig(
                        state.id,
                        updatedConfig.toJson(),
                      );

                      // Dismiss the bottom sheet on success
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text("Worker config updated successfully"),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      // Pass the error back up so the editor widget displays it
                      throw Exception(e.toString());
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ctrlBtn(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: color, size: 18),
      label: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        backgroundColor: color.withValues(alpha: 0.1),
      ),
    );
  }
}
