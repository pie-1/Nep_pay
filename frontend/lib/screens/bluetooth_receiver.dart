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
  bool _isListening = false;

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
    setState(() {
      _connectionStatus = 'Checking Bluetooth...';
    });

    // Check if Bluetooth is available
    final isAvailable = await _bleService.isBluetoothAvailable();
    if (!isAvailable) {
      setState(() {
        _connectionStatus = 'Bluetooth not available. Please enable Bluetooth.';
      });
      return;
    }

    // Listen to connection status updates
    _statusSubscription = _bleService.connectionStatusStream.listen((status) {
      setState(() {
        _connectionStatus = status;
      });
    });

    // Listen to incoming messages
    _messageSubscription = _bleService.messageStream.listen((message) {
      _handleIncomingMessage(message);
    });

    setState(() {
      _connectionStatus = 'Ready to receive payments. Make this device discoverable.';
      _isListening = true;
    });
  }

  void _handleIncomingMessage(Map<String, dynamic> message) {
    if (message['type'] == 'payment_request') {
      setState(() {
        _pendingRequests.add(message);
      });
      
      // Show notification
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment request received from ${message['sender_name']}'),
          backgroundColor: Colors.blue,
          action: SnackBarAction(
            label: 'View',
            onPressed: () {
              // Scroll to bottom to show the request
            },
          ),
        ),
      );
    }
  }

  Future<void> _respondToPayment(Map<String, dynamic> request, bool accept, {String? reason}) async {
    final transactionId = request['transaction_id'];
    
    // Send response
    await _bleService.sendPaymentResponse(
      transactionId: transactionId,
      accepted: accept,
      reason: reason,
    );

    if (accept) {
      // Add to transaction queue
      await TransactionQueue.queue({
        'method': 'P2P-BT',
        'name': request['sender_name'],
        'phone': request['sender_phone'],
        'amount': request['amount'],
        'description': request['description'] ?? '',
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'completed',
        'transaction_id': transactionId,
        'type': 'received',
        'device_name': _bleService.connectedDeviceName,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment of ₹${request['amount']} accepted'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment request rejected'),
          backgroundColor: Colors.red,
        ),
      );
    }

    // Remove from pending requests
    setState(() {
      _pendingRequests.removeWhere((req) => req['transaction_id'] == transactionId);
    });
  }

  void _showPaymentDialog(Map<String, dynamic> request) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.payment, color: Colors.blue),
            SizedBox(width: 8),
            Text('Payment Request'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('From:', request['sender_name'] ?? 'Unknown'),
            _buildInfoRow('Phone:', request['sender_phone'] ?? 'Unknown'),
            _buildInfoRow('Amount:', '₹${request['amount'] ?? 0}'),
            if (request['description']?.isNotEmpty == true)
              _buildInfoRow('Description:', request['description']),
            _buildInfoRow('Time:', _formatTime(request['timestamp'])),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _respondToPayment(request, false, reason: 'Rejected by user');
            },
            child: const Text('Reject', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _respondToPayment(request, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Accept', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return 'Unknown';
    try {
      final dateTime = DateTime.parse(timestamp);
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        title: const Text(
          'Receive Payment',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 22),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Section
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isListening ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                      size: 28,
                      color: _isListening ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'BinaNet Pay Receiver',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          Text(
                            _isListening ? 'Listening for payments' : 'Not listening',
                            style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.onPrimaryContainer.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // Status Card
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 20,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _connectionStatus,
                              style: TextStyle(
                                fontSize: 16,
                                color: colorScheme.onSurface.withOpacity(0.8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Instructions
              if (_isListening && _pendingRequests.isEmpty)
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Icon(
                          Icons.phone_bluetooth_speaker,
                          size: 48,
                          color: colorScheme.primary.withOpacity(0.7),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Ready to Receive',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Make sure this device is discoverable and wait for payment requests from nearby devices.',
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.onSurface.withOpacity(0.7),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              
              // Pending Requests
              if (_pendingRequests.isNotEmpty) ...[
                Text(
                  'Pending Requests (${_pendingRequests.length})',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: _pendingRequests.length,
                    itemBuilder: (context, index) {
                      final request = _pendingRequests[index];
                      return Card(
                        elevation: 3,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.payment,
                              color: Colors.blue,
                              size: 24,
                            ),
                          ),
                          title: Text(
                            '₹${request['amount']} from ${request['sender_name']}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Phone: ${request['sender_phone']}'),
                              if (request['description']?.isNotEmpty == true)
                                Text('Note: ${request['description']}'),
                              Text('Time: ${_formatTime(request['timestamp'])}'),
                            ],
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () => _showPaymentDialog(request),
                        ),
                      );
                    },
                  ),
                ),
              ] else
                const Spacer(),
              
              // Instructions at bottom
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outline.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Keep this screen open to receive payment requests via Bluetooth',
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}