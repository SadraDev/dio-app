import 'package:flutter/material.dart';
import '../services/trade_service.dart';

/// Numeric order ticket. Works for both market execution and pending limit
/// orders, with optional SL/TP. Submits through TradeService (real API).
class TradeDialog extends StatefulWidget {
  final String symbol;
  final bool isPending;

  /// Pre-fill price (e.g. current close) for pending orders.
  final double? suggestedPrice;

  const TradeDialog({
    super.key,
    required this.symbol,
    required this.isPending,
    this.suggestedPrice,
  });

  @override
  State<TradeDialog> createState() => _TradeDialogState();
}

class _TradeDialogState extends State<TradeDialog> {
  final _volumeController = TextEditingController(text: "0.01");
  final _priceController = TextEditingController();
  final _slController = TextEditingController();
  final _tpController = TextEditingController();
  String _side = 'buy';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.isPending) {
      _side = 'buy_limit';
      if (widget.suggestedPrice != null) {
        _priceController.text = widget.suggestedPrice!.toStringAsFixed(5);
      }
    }
  }

  @override
  void dispose() {
    _volumeController.dispose();
    _priceController.dispose();
    _slController.dispose();
    _tpController.dispose();
    super.dispose();
  }

  InputDecoration _decor(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.grey),
    filled: true,
    fillColor: const Color(0xff0f172a),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
  );

  void _toast(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _submit() async {
    final volume = double.tryParse(_volumeController.text.trim());
    final price = double.tryParse(_priceController.text.trim());
    final sl = double.tryParse(_slController.text.trim());
    final tp = double.tryParse(_tpController.text.trim());

    if (volume == null || volume <= 0) {
      _toast("Invalid volume", Colors.red);
      return;
    }
    if (widget.isPending && (price == null || price <= 0)) {
      _toast("Invalid price", Colors.red);
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (widget.isPending) {
        await TradeService.placePending(
          symbol: widget.symbol,
          volume: volume,
          side: _side,
          price: price!,
          sl: sl,
          tp: tp,
        );
      } else {
        await TradeService.openMarket(
          symbol: widget.symbol,
          volume: volume,
          side: _side,
          sl: sl,
          tp: tp,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
      _toast("Order sent successfully!", Colors.green);
    } catch (e) {
      _toast("Order failed: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sideItems = widget.isPending
        ? const [
      DropdownMenuItem(value: 'buy_limit', child: Text("Buy Limit")),
      DropdownMenuItem(value: 'sell_limit', child: Text("Sell Limit")),
    ]
        : const [
      DropdownMenuItem(value: 'buy', child: Text("Buy")),
      DropdownMenuItem(value: 'sell', child: Text("Sell")),
    ];

    return AlertDialog(
      backgroundColor: const Color(0xff162033),
      title: Text(
        "${widget.isPending ? 'Set Pending Order' : 'Market Execution'} - ${widget.symbol}",
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _side,
              dropdownColor: const Color(0xff162033),
              style: const TextStyle(color: Colors.white),
              decoration: _decor("Side"),
              items: sideItems,
              onChanged: (v) => setState(() => _side = v!),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _volumeController,
              style: const TextStyle(color: Colors.white),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _decor("Volume (lots)"),
            ),
            if (widget.isPending) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _priceController,
                style: const TextStyle(color: Colors.white),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _decor("Entry price"),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _slController,
              style: const TextStyle(color: Colors.white),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _decor("Stop Loss (optional)"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tpController,
              style: const TextStyle(color: Colors.white),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _decor("Take Profit (optional)"),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _isLoading ? Colors.grey : Colors.blue,
          ),
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
              : const Text("Confirm"),
        ),
      ],
    );
  }
}
