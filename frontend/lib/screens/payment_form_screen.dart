// 🔹 screens/payment_form_screen.dart
import 'package:flutter/material.dart';
import '../services/transactions_queue.dart';

class PaymentFormScreen extends StatefulWidget {
  final String name;
  final String phone;
  final double expectedAmount;

  const PaymentFormScreen({
    super.key,
    required this.name,
    required this.phone,
    required this.expectedAmount,
  });

  @override
  State<PaymentFormScreen> createState() => _PaymentFormScreenState();
}

class _PaymentFormScreenState extends State<PaymentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();

  void _submit() async {
    if (_formKey.currentState!.validate()) {
      final enteredAmount = double.parse(_amountController.text.trim());
      if (enteredAmount != widget.expectedAmount) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Amount Mismatch'),
            content: const Text('Entered amount does not match the requested amount.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      await TransactionQueue.queue({
        'method': 'QR',
        'name': widget.name,
        'phone': widget.phone,
        'amount': enteredAmount,
        'timestamp': DateTime.now().toIso8601String(),
      });

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Payment Queued'),
          content: const Text('Your payment has been queued for offline processing.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Amount'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pay to: ${widget.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Phone: ${widget.phone}', style: TextStyle(color: Colors.grey[400])),
            const SizedBox(height: 16),
            Text('Requested Amount: ₹${widget.expectedAmount}', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Enter Amount',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter amount';
                  final n = double.tryParse(v.trim());
                  if (n == null || n <= 0) return 'Enter valid amount';
                  return null;
                },
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Confirm & Queue Payment'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
