import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../services/transactions_queue.dart';

class ReceiverBluetoothServerScreen extends StatefulWidget {
  const ReceiverBluetoothServerScreen({super.key});

  @override
  State<ReceiverBluetoothServerScreen> createState() => _ReceiverBluetoothServerScreenState();
}

class _ReceiverBluetoothServerScreenState extends State<ReceiverBluetoothServerScreen> {
  final BLEService _bleService = BLEService();
  String _connectionStatus = 'Initializing...';
  List<Map<String, dynamic>> _pendingRequests = [];
  StreamSubscription? _messageSubscription;
  StreamSubscription? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _initializeBluetooth();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _statusSubscription?.cancel();
    _bleService.disconnect();
    super.dispose();
  }

  Future<void> _initializeBluetooth() async {
    // Check if Bluetooth is available
    final isAvailable = await _bleService.isBluetoothAvailable();
    if (!isAvailable) {
      setState(() {
        _connectionStatus = 'Bluetooth not available. Please enable Bluetooth.';
      });
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Receiver'),
      ),
      body: Center(
        child: Text(_connectionStatus),
      ),
    );
  }
}