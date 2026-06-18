import 'package:flutter/material.dart';
import '../services/api_client.dart';

class TradeDialog extends StatefulWidget {
  final String symbol;
  final bool isPending;

  const TradeDialog({super.key, required this.symbol, required this.isPending});

  @override
  State<TradeDialog> createState() => _TradeDialogState();
}

class _TradeDialogState extends State<TradeDialog> {
  final _volumeController = TextEditingController(text: "0.01");
  final _priceController = TextEditingController();
  String _side = 'buy';
  bool _isLoading = false;

  // Shared decoration for inputs to match your app style
  InputDecoration _inputDecor(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.grey),
    filled: true,
    fillColor: const Color(0xff0f172a),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
  );

  Future<void> _submitOrder() async {
    // Basic Validation
    final volume = double.tryParse(_volumeController.text);
    final price = widget.isPending
        ? double.tryParse(_priceController.text)
        : null;

    if (volume == null || volume <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Invalid volume"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (widget.isPending && (price == null || price <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Invalid price"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final payload = {
        "symbol": widget.symbol,
        "volume": volume,
        "order_type": _side,
        if (widget.isPending) "price": price,
      };

      // Ensure your ApiClient handles the authorization header automatically
      await ApiClient.post('/execution/order/', body: payload);

      if (!mounted) return;

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Order sent successfully!"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Order failed: ${e.toString()}"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xff162033),
      title: Text(
        "${widget.isPending ? 'Set Order' : 'Market Execution'} - ${widget.symbol}",
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            value: _side,
            dropdownColor: const Color(0xff162033),
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecor("Side"),
            items: const [
              DropdownMenuItem(value: 'buy', child: Text("Buy")),
              DropdownMenuItem(value: 'sell', child: Text("Sell")),
            ],
            onChanged: (v) => setState(() => _side = v!),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _volumeController,
            style: const TextStyle(color: Colors.white),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _inputDecor("Volume"),
          ),
          if (widget.isPending) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _priceController,
              style: const TextStyle(color: Colors.white),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: _inputDecor("Price"),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _isLoading ? Colors.grey : Colors.blue,
          ),
          onPressed: _isLoading ? null : _submitOrder,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text("Confirm"),
        ),
      ],
    );
  }
}
