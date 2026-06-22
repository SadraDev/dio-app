import 'package:flutter/material.dart';
import '../models/trading_data.dart';
import '../services/trade_service.dart';

/// Bottom sheet to manage live positions and pending orders for a symbol.
/// Close / modify SL-TP / cancel — all through the real execution API.
class PositionsSheet extends StatefulWidget {
  final String symbol;
  final TradingOverlayData data;

  /// Called after any successful action so the parent can refresh overlays.
  final Future<void> Function() onChanged;

  const PositionsSheet({
    super.key,
    required this.symbol,
    required this.data,
    required this.onChanged,
  });

  @override
  State<PositionsSheet> createState() => _PositionsSheetState();
}

class _PositionsSheetState extends State<PositionsSheet> {
  int? _busyTicket;

  void _toast(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _run(int ticket, Future<dynamic> Function() action, String okMsg) async {
    setState(() => _busyTicket = ticket);
    try {
      await action();
      await widget.onChanged();
      _toast(okMsg, Colors.green);
    } catch (e) {
      _toast("Failed: $e", Colors.redAccent);
    } finally {
      if (mounted) setState(() => _busyTicket = null);
    }
  }

  Future<void> _confirmClose(OpenPosition p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xff162033),
        title: const Text("Close position?", style: TextStyle(color: Colors.white)),
        content: Text(
          "Close #${p.ticket} ${p.typeStr.toUpperCase()} ${p.volume} lots at market?",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Close", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      _run(p.ticket, () => TradeService.closePosition(p.ticket), "Position closed");
    }
  }

  Future<void> _modify(OpenPosition p) async {
    final slCtrl =
    TextEditingController(text: p.sl > 0 ? p.sl.toStringAsFixed(5) : "");
    final tpCtrl =
    TextEditingController(text: p.tp > 0 ? p.tp.toStringAsFixed(5) : "");

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xff162033),
        title: Text("Modify #${p.ticket}",
            style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _numField(slCtrl, "Stop Loss (price)"),
            const SizedBox(height: 10),
            _numField(tpCtrl, "Take Profit (price)"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Save", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (ok == true) {
      final sl = double.tryParse(slCtrl.text.trim());
      final tp = double.tryParse(tpCtrl.text.trim());
      _run(
        p.ticket,
            () => TradeService.modifyPosition(p.ticket, sl: sl ?? 0.0, tp: tp ?? 0.0),
        "SL/TP updated",
      );
    }
  }

  Widget _numField(TextEditingController c, String label) {
    return TextField(
      controller: c,
      style: const TextStyle(color: Colors.white),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: const Color(0xff0f172a),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final positions = widget.data.positions;
    final orders = widget.data.orders;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xff111827),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text("${widget.symbol} — Positions & Orders",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              _section("Open Positions (${positions.length})"),
              if (positions.isEmpty)
                _empty("No open positions")
              else
                ...positions.map(_positionTile),

              const SizedBox(height: 16),
              _section("Pending Orders (${orders.length})"),
              if (orders.isEmpty)
                _empty("No pending orders")
              else
                ...orders.map(_orderTile),

              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _section(String t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(t,
        style: const TextStyle(
            color: Colors.green, fontWeight: FontWeight.bold)),
  );

  Widget _empty(String t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(t, style: const TextStyle(color: Colors.white38)),
  );

  Widget _positionTile(OpenPosition p) {
    final isBuy = p.typeStr.toLowerCase() == 'buy';
    final busy = _busyTicket == p.ticket;
    final plColor = p.profit >= 0 ? Colors.green : Colors.redAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xff162033),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isBuy ? Colors.green : Colors.redAccent)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(p.typeStr.toUpperCase(),
                    style: TextStyle(
                        color: isBuy ? Colors.green : Colors.redAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Text("#${p.ticket}",
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const Spacer(),
              Text("${p.profit >= 0 ? '+' : '-'}\$${p.profit.abs().toStringAsFixed(2)}",
                  style: TextStyle(
                      color: plColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "${p.volume} lots @ ${p.priceOpen.toStringAsFixed(5)}   "
                "SL ${p.sl > 0 ? p.sl.toStringAsFixed(5) : '—'}   "
                "TP ${p.tp > 0 ? p.tp.toStringAsFixed(5) : '—'}",
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : () => _modify(p),
                  icon: const Icon(Icons.tune, size: 16, color: Colors.blueAccent),
                  label: const Text("Modify SL/TP",
                      style: TextStyle(color: Colors.blueAccent)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.blueAccent),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: busy ? null : () => _confirmClose(p),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                  child: busy
                      ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                      : const Text("Close", style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _orderTile(PendingOrder o) {
    final busy = _busyTicket == o.ticket;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xff162033),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, color: Colors.amber, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "#${o.ticket}  ${o.typeStr.replaceAll('_', ' ').toUpperCase()}\n"
                  "${o.volumeInitial} lots @ ${o.priceOpen.toStringAsFixed(5)}",
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => _run(o.ticket, () => TradeService.cancelOrder(o.ticket),
                "Order cancelled"),
            child: busy
                ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.redAccent))
                : const Text("Cancel", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}
