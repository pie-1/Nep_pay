import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/transactions_queue.dart';
import 'bluetooth_sender.dart';

class QRScanScreen extends StatefulWidget {
  const QRScanScreen({super.key});

  @override
  State<QRScanScreen> createState() => _QRScanScreenState();
}

class _QRScanScreenState extends State<QRScanScreen> {
  bool _scanned = false;
  final MobileScannerController _controller = MobileScannerController();

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;

    final barcode = capture.barcodes.first;
    final data = barcode.rawValue;
    _handleScannedData(data);
  }

  void _handleScannedData(String? data) {
    if (data != null && data.trim().isNotEmpty) {
      try {
        final Map<String, dynamic> parsed = jsonDecode(data);
        if (parsed.containsKey('name') && parsed.containsKey('phone') && parsed.containsKey('expected_amount')) {
          setState(() => _scanned = true);
          // Instead of PaymentFormScreen, go to BluetoothSenderScreen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BluetoothSenderScreen(
                receiverName: parsed['name'],
                receiverPhone: parsed['phone'],
                amount: double.tryParse(parsed['expected_amount'].toString()) ?? 0.0,
              ),
            ),
          );
        } else {
          throw const FormatException('Missing fields');
        }
      } catch (_) {
        _showErrorDialog('Invalid QR', 'This QR code is not valid for Bina Net payments.');
      }
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan to Pay'),
        centerTitle: true,
      ),
      body: Container(
        color: colorScheme.surface,
        child: Column(
          children: [
            const SizedBox(height: 24),
            const Text(
              'Scan Receiver\'s QR',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
